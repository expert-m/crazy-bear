REMOTE_ARDUINO_PORT = /dev/ttyUSB0
LOCAL_ARDUINO_PORT = /dev/ttyUSB0


# Main commands

bash:
	docker compose run --rm core bash

prod-bash:
	docker compose -p crazy_bear -f docker-compose.prod.yml run --rm core bash

run:
	poetry run python3 ./__main__.py

mypy:
	poetry run mypy ./__main__.py --ignore-missing-imports

ipython:
	poetry run python3

test:
	poetry run pytest ./libs ./project

format:
	autoflake --remove-all-unused-imports --recursive --remove-unused-variables --in-place --exclude=__init__.py libs project
	black --skip-string-normalization -t py311 --line-length=120 libs project

full_check: mypy test


# Commands for working with the server

deploy:
	@$(MAKE) --no-print-directory bump_version
	@$(MAKE) --no-print-directory scp
	@$(MAKE) --no-print-directory fast_stop
	@$(MAKE) --no-print-directory rewrite
	@$(MAKE) --no-print-directory up

redeploy:
	@$(MAKE) --no-print-directory bump_version
	@$(MAKE) --no-print-directory scp
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory rewrite
	@$(MAKE) --no-print-directory build
	@$(MAKE) --no-print-directory up


push:
	@$(MAKE) --no-print-directory scp
	@$(MAKE) --no-print-directory rewrite

compile_arduino:
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory fast_compile_arduino
	@$(MAKE) --no-print-directory up

fast_compile_arduino:
	@$(MAKE) --no-print-directory scp
	@$(MAKE) --no-print-directory rewrite
	@$(MAKE) --no-print-directory compile_arduino_on_server

compile_arduino_on_server: CMD := "\
	export PATH='$$PATH:/home/ubuntu/bin' && \
	echo 'Compiling...' && \
	arduino-cli compile ~/crazy_bear/hardware/arduino/core --port $(REMOTE_ARDUINO_PORT) --fqbn arduino:avr:nano:cpu=atmega328old --verify && \
	echo 'Uploading...' && \
	arduino-cli upload ~/crazy_bear/hardware/arduino/core --port $(REMOTE_ARDUINO_PORT) --fqbn arduino:avr:nano:cpu=atmega328old --verify && \
	echo 'Done.'\
"
compile_arduino_on_server: _run_remote_cmd

arduino_monitor_on_server: CMD := "\
	export PATH='$$PATH:/home/ubuntu/bin' && \
	echo 'Compiling...' && \
	arduino-cli compile ~/crazy_bear/hardware/arduino/core --port $(REMOTE_ARDUINO_PORT) --fqbn arduino:avr:nano:cpu=atmega328old --verify && \
	echo 'Uploading...' && \
	arduino-cli upload ~/crazy_bear/hardware/arduino/core --port $(REMOTE_ARDUINO_PORT) --fqbn arduino:avr:nano:cpu=atmega328old --verify && \
	echo 'Done.'\
"
arduino_monitor_on_server: _run_remote_cmd

rewrite: CMD := "\
	sudo rm ./crazy_bear -r && \
	mkdir crazy_bear && \
	unzip ./crazy_bear.zip -d ./crazy_bear && \
	rm ./crazy_bear.zip\
"
rewrite: _run_remote_cmd

up: CMD = "cd crazy_bear && docker compose -p crazy_bear -f docker-compose.prod.yml up -d"
up: _run_remote_cmd

fast_stop: CMD = "cd crazy_bear && docker compose -p crazy_bear -f docker-compose.prod.yml stop core"
fast_stop: _run_remote_cmd

stop: CMD = "cd crazy_bear && docker compose -p crazy_bear -f docker-compose.prod.yml stop"
stop: _run_remote_cmd

build: CMD = "cd crazy_bear && docker compose -p crazy_bear -f docker-compose.prod.yml build"
build: _run_remote_cmd

scp:
	@echo "Creating zip..."
	@zip -r crazy_bear.zip \
	    $(shell git ls-files) \
	    ./hardware/arduino/core/JsonRadioTransmitter \
	    ./hardware/arduino/viewer/JsonRadioTransmitter \
	    ./config/
	@echo "Coping to RPi..."
	@scp ./crazy_bear.zip pi:~
	@echo "Cleaning..."
	@rm ./crazy_bear.zip

_run_remote_cmd:
	@echo "RUN:" $(CMD)
	@ssh pi $(CMD)


# Arduino

arduino_list:
	arduino-cli board list

arduino_compile:
	echo "Compiling..."
	arduino-cli compile ./hardware/arduino/viewer --port $(LOCAL_ARDUINO_PORT) --fqbn arduino:avr:nano:cpu=atmega328old --verify
	echo "Done."

arduino_build:
	echo "Compiling..."
	arduino-cli compile ./hardware/arduino/viewer --port $(LOCAL_ARDUINO_PORT) --fqbn arduino:avr:nano:cpu=atmega328old --verify
	echo "Uploading..."
	arduino-cli upload ./hardware/arduino/viewer --port $(LOCAL_ARDUINO_PORT) --fqbn arduino:avr:nano:cpu=atmega328old --verify
	echo "Done."

arduino_monitor:
	arduino-cli monitor --port $(LOCAL_ARDUINO_PORT) --fqbn arduino:avr:nano:cpu=atmega328old


# Other

bump_version:
	poetry run python3 -c "from libs.casual_utils.version_manager import VersionDetails; \
                           version_details = VersionDetails(); version_details.increase(); \
                           version_details.save()"

freeze:
	poetry export -f requirements.txt --output requirements.txt --without-hashes
