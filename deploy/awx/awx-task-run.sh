#!/bin/bash -l
# Run the AWX task supervisor directly, skipping launch_awx_task.sh's
# `awx-manage provision_instance` (which fails outside K8s). The `-l` login
# shell activates the awx venv. awx-init.sh provisions the instance once.
exec supervisord -c /etc/supervisord_task.conf
