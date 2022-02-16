import datetime
import logging
import queue
import threading
import typing
from time import sleep

from ..base import BaseTaskQueue, BaseWorker, TaskPriorityQueue
from ..constants import TaskPriorities, TaskStatus
from ..dto import RetryPolicy, Task, default_retry_policy
from ..exceptions import RepeatTask
from ...common.utils import synchronized_method


__all__ = (
    'MemTaskQueue',
    'ThreadWorker',
    'UniqueTaskQueue',
)


class MemTaskQueue(BaseTaskQueue):
    _tasks: TaskPriorityQueue

    def __init__(self) -> None:
        self._tasks = TaskPriorityQueue()

    def __len__(self) -> int:
        return self._tasks.qsize()

    def put_task(self, task: Task) -> None:
        task.status = TaskStatus.PENDING

        logging.debug('Put %s to MemTaskQueue', task)

        self._tasks.put(task)

    def get(self) -> typing.Optional[Task]:
        try:
            return self._tasks.get(block=False)
        except queue.Empty:
            return None


class ThreadWorker(BaseWorker):
    task_queue: BaseTaskQueue
    _is_run: threading.Event
    _thread: threading.Thread
    _on_close: typing.Optional[typing.Callable]
    _getting_delay: float = 0.2

    def __init__(self, *,
                 task_queue: BaseTaskQueue,
                 on_close: typing.Optional[typing.Callable] = None) -> None:
        self.task_queue = task_queue
        self._on_close = on_close
        self._is_run = threading.Event()
        self._thread = threading.Thread(target=self._process_tasks)

    @property
    def is_run(self) -> bool:
        return self._is_run.is_set()

    def run(self) -> None:
        if self.is_run:
            return

        logging.info(f'Run {self.__class__.__name__}...')
        self._is_run.set()
        self._thread.start()
        logging.info(f'{self.__class__.__name__} is ready.')

    def stop(self) -> None:
        if not self.is_run:
            return

        self._is_run.clear()

        if len(self.task_queue):
            logging.warning(f'TaskQueue is stopped, but there are {len(self.task_queue)} tasks in queue.')

        self._thread.join()

    def _process_tasks(self) -> typing.NoReturn:
        while self.is_run:
            task = self.task_queue.get()

            if task is None:
                logging.debug('Wait tasks')
                sleep(self._getting_delay)
                continue

            logging.debug('Get %s from MemTaskQueue', task)

            try:
                task.run()
            except RepeatTask:
                self.task_queue.put_task(task)
            except Exception as e:
                logging.exception(e)

        if self._on_close is not None:
            self._on_close()


class UniqueTaskQueue:
    _lock: threading.Lock
    _tasks_map: typing.Dict[typing.Callable, Task]
    _task_queue: BaseTaskQueue

    def __init__(self, *, task_queue: BaseTaskQueue) -> None:
        self._task_queue = task_queue
        self._tasks_map = {}
        self._lock = threading.Lock()

    def push(self,
             target: typing.Callable, *,
             priority: int = TaskPriorities.MEDIUM,
             retry_policy: RetryPolicy = default_retry_policy,
             run_after: typing.Optional[datetime.datetime] = None) -> typing.Optional[Task]:
        if not self._task_is_finished(target):
            return None

        task = self._task_queue.put(target, priority=priority, retry_policy=retry_policy, run_after=run_after)

        if task is not None:
            self._track(task)

        return task

    @synchronized_method
    def _track(self, task: Task) -> None:
        self._tasks_map[task.target] = task

    @synchronized_method
    def _task_is_finished(self, target: typing.Callable) -> bool:
        if target not in self._tasks_map:
            return True

        if self._tasks_map[target].status in (TaskStatus.FINISHED, TaskStatus.FAILED,):
            del self._tasks_map[target]
            return True

        return False
