#!/bin/sh
# The facts hack/dump-image.sh and hack/dump-host.sh collect: run as root, inside
# an image or on a machine, with the same output either way.
echo "### rpms"
rpm -qa --qf "%{NAME} %{VERSION}-%{RELEASE}\n" 2>/dev/null | sort
echo "### os"
cat /etc/os-release 2>/dev/null | grep -E "^(ID|VERSION_ID|PRETTY_NAME)="
echo "### pythons"
for p in /usr/bin/python3* /usr/local/bin/python3* $(find / -xdev -path "*/venv*/bin/python3" -o -xdev -path "*/.venv/bin/python3" 2>/dev/null); do
  [ -x "$p" ] || continue
  case "$p" in *-config) continue;; esac
  echo "## $p $($p -c "import sys;print(sys.prefix)" 2>/dev/null)"
  $p -m pip list --format=freeze --disable-pip-version-check 2>/dev/null \
    || $p -c "import importlib.metadata as m;[print(d.metadata[\"Name\"]+\"==\"+d.version) for d in m.distributions()]" 2>/dev/null | sort -f
done
echo "### installer"
find / -xdev -name INSTALLER -path "*dist-info*" 2>/dev/null | while read f; do echo "$(cat $f) $(dirname $f)"; done | awk "{print \$1}" | sort | uniq -c
echo "### layout"
for d in /etc/tower /var/lib/awx /etc/ansible-automation-platform /var/lib/ansible-automation-platform /opt /etc/supervisord.conf /etc/supervisord.d /etc/nginx /etc/receptor /var/lib/receptor /home /runner /var/lib/pulp /etc/pulp /app /usr/share/nginx /var/run/receptor /run/receptor; do
  [ -e "$d" ] && find "$d" -maxdepth 2 -printf "%u:%g %m %y %p\n" 2>/dev/null | sort -k4 | head -60
done
echo "### usr-bin"
ls /usr/bin /usr/local/bin 2>/dev/null | grep -E "manage|receptor|runner|dumb-init|supervisor|uwsgi|gunicorn|daphne|nginx|podman|ansible|launch|start|wait|pulp|galaxy|aap|awx|eda" | sort -u
echo "### passwd"
grep -vE "nologin$|/sbin/(halt|shutdown)|^sync:" /etc/passwd
awk -F: "\$3>=999" /etc/passwd
echo "### subuid"
wc -c /etc/subuid /etc/subgid 2>/dev/null
