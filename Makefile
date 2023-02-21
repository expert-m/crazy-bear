# Commands for working with the server

deploy: bump_version scp fast_stop rewrite up

push: scp rewrite

compile_arduino: stop fast_compile_arduino up

fast_compile_arduino: scp rewrite compile_arduino_on_server

compile_arduino_on_server: CMD := "\
	export PATH='$$PATH:/home/ubuntu/bin' && \
	echo 'Compiling...' && \
	arduino-cli compile ~/crazy_bear/hardware/arduino/core --port /dev/ttyUSB0 --fqbn arduino:avr:nano:cpu=atmega328old --verify && \
	echo 'Uploading...' && \
	arduino-cli upload ~/crazy_bear/hardware/arduino/core --port /dev/ttyUSB0 --fqbn arduino:avr:nano:cpu=atmega328old --verify && \
	echo 'Done.'\
"
compile_arduino_on_server: _run_remote_cmd

rewrite: CMD := "\
	sudo rm ./crazy_bear -r && \
	mkdir crazy_bear && \
	unzip ./crazy_bear.zip -d ./crazy_bear && \
	rm ./crazy_bear.zip\
"
rewrite: _run_remote_cmd

up: CMD = "cd crazy_bear && docker-compose -p crazy_bear -f docker-compose.prod.yml up -d"
up: _run_remote_cmd

fast_stop: CMD = "cd crazy_bear && docker-compose -p crazy_bear -f docker-compose.prod.yml stop core"
fast_stop: _run_remote_cmd

stop: CMD = "cd crazy_bear && docker-compose -p crazy_bear -f docker-compose.prod.yml stop"
stop: _run_remote_cmd

build: CMD = "cd crazy_bear && docker-compose -p crazy_bear -f docker-compose.prod.yml build"
build: _run_remote_cmd

bump_version:
	python3 -c "from dotenv import load_dotenv; load_dotenv('envs/local.env'); \
               from project.config.utils import VersionDetails; \
               version_details = VersionDetails(); version_details.patch += 1; \
               version_details.save()"

scp:
	echo "Creating zip..."
	zip -r crazy_bear.zip $(shell git ls-files) ./envs/prod.env
	echo "Coping to RPi..."
	scp ./crazy_bear.zip pi:~
	rm ./crazy_bear.zip

_run_remote_cmd:
	echo "RUN: $(CMD)"
	ssh pi $(CMD)


# Arduino

arduino_list:
	arduino-cli board list

arduino_compile:
	echo "Compiling..."
	arduino-cli compile ./hardware/arduino/viewer --port /dev/ttyUSB0 --fqbn arduino:avr:nano:cpu=atmega328old --verify
	echo "Done."

arduino_build:
	echo "Compiling..."
	arduino-cli compile ./hardware/arduino/viewer --port /dev/ttyUSB0 --fqbn arduino:avr:nano:cpu=atmega328old --verify
	echo "Uploading..."
	arduino-cli upload ./hardware/arduino/viewer --port /dev/ttyUSB0 --fqbn arduino:avr:nano:cpu=atmega328old --verify
	echo "Done."

arduino_monitor:
	arduino-cli monitor --port /dev/ttyUSB0 --fqbn arduino:avr:nano:cpu=atmega328old


# Other

freeze:
	poetry export -f requirements.txt --output requirements.txt --without-hashes
