import datetime
import threading
import typing

import schedule

from .. import events
from ..base import BaseModule, Command
from ..constants import (
    AUTO_SECURITY_IS_ENABLED, CAMERA_IS_AVAILABLE, SECURITY_IS_ENABLED, USER_IS_CONNECTED_TO_ROUTER,
    USE_CAMERA,
)
from ...common.constants import AUTO, OFF, ON
from ...task_queue import TaskPriorities
from ...common.utils import single_synchronized, synchronized
from ...messengers.constants import BotCommands


__all__ = (
    'AutoSecurity',
)


class AutoSecurity(BaseModule):
    initial_state = {
        AUTO_SECURITY_IS_ENABLED: False,
    }
    _last_movement_at: typing.Optional[datetime.datetime] = None
    _camera_was_not_used: bool = False
    _twenty_minutes: datetime.timedelta = datetime.timedelta(minutes=20)
    _lock_for_last_movement_at: threading.RLock

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)

        self._lock_for_last_movement_at = threading.RLock()

    def init_schedule(self, scheduler: schedule.Scheduler) -> tuple:
        return (
            scheduler.every(1).minute.do(
                self.unique_task_queue.push,
                self._check_camera_status,
                priority=TaskPriorities.HIGH,
            ),
        )

    def subscribe_to_events(self) -> tuple:
        return (
            *super().subscribe_to_events(),
            events.motion_detected.connect(self._update_last_movement_at),
        )

    def process_command(self, command: Command) -> typing.Any:
        if command.name == BotCommands.SECURITY:
            if command.first_arg == AUTO:
                if command.second_arg == ON:
                    self._enable_auto_security()
                elif command.second_arg == OFF:
                    self._disable_auto_security()
                else:
                    return False
            elif command.first_arg == ON:
                self.state[SECURITY_IS_ENABLED] = True
                self.messenger.send_message('Security is enabled')
            elif command.first_arg == OFF:
                self.state[SECURITY_IS_ENABLED] = False
                self.messenger.send_message('Security is disabled')
            else:
                return False

            return True

        return False

    @synchronized
    def disable(self) -> None:
        super().disable()

        if self.state[AUTO_SECURITY_IS_ENABLED]:
            self._disable_auto_security()

    @synchronized
    def _enable_auto_security(self) -> None:
        self.state[AUTO_SECURITY_IS_ENABLED] = True

        events.user_is_connected_to_router.connect(self._process_user_is_connected_to_router)
        events.user_is_disconnected_to_router.connect(self._process_user_is_disconnected_to_router)

        self.messenger.send_message('Auto security is enabled')

    @synchronized
    def _disable_auto_security(self) -> None:
        use_camera: bool = self.state[USE_CAMERA]

        self.state[AUTO_SECURITY_IS_ENABLED] = False

        if self._camera_was_not_used and use_camera:
            self._run_command(BotCommands.CAMERA, OFF)

        self._camera_was_not_used = False

        events.user_is_connected_to_router.disconnect(self._process_user_is_connected_to_router)
        events.user_is_disconnected_to_router.disconnect(self._process_user_is_disconnected_to_router)

        self.messenger.send_message('Auto security is disabled')

    @synchronized
    def _update_last_movement_at(self) -> None:
        with self._lock_for_last_movement_at:
            self._last_movement_at = datetime.datetime.now()

        if (not self.state[USER_IS_CONNECTED_TO_ROUTER]
                and not self.state[USE_CAMERA]
                and self.state[CAMERA_IS_AVAILABLE]):
            self._camera_was_not_used = True
            self._run_command(BotCommands.CAMERA, ON)

    def _process_user_is_connected_to_router(self) -> None:
        if not self.state[AUTO_SECURITY_IS_ENABLED]:
            return

        if self.state[SECURITY_IS_ENABLED]:
            self.messenger.send_message('The owner is found')
            self._run_command(BotCommands.SECURITY, OFF)

    def _process_user_is_disconnected_to_router(self) -> None:
        if not self.state[AUTO_SECURITY_IS_ENABLED]:
            return

        if not self.state[SECURITY_IS_ENABLED]:
            self.messenger.send_message('The owner is not found')
            self._run_command(BotCommands.SECURITY, ON)

    @single_synchronized
    def _check_camera_status(self) -> None:
        if not self.state[AUTO_SECURITY_IS_ENABLED]:
            return

        user_is_connected: bool = self.state[USER_IS_CONNECTED_TO_ROUTER]
        # security_is_enabled: bool = self.state[SECURITY_IS_ENABLED]

        # if user_is_connected and security_is_enabled:
        #     self.messenger.send_message('The owner is found')
        #     self._run_command(BotCommands.SECURITY, OFF)
        #     return
        #
        # if not user_is_connected and not security_is_enabled:
        #     self.messenger.send_message('The owner is not found')
        #     self._run_command(BotCommands.SECURITY, ON)
        #     return

        with self._lock_for_last_movement_at:
            now = datetime.datetime.now()
            has_movement = self._last_movement_at and now - self._last_movement_at <= self._twenty_minutes

        use_camera: bool = self.state[USE_CAMERA]

        if (user_is_connected or not has_movement) and self._camera_was_not_used and use_camera:
            self._camera_was_not_used = False
            self._run_command(BotCommands.CAMERA, OFF)
