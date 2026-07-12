# /etc/tower/conf.d/ace.py — AWX (controller) settings for the ACE control-plane test.
# Point DB at ace-postgres and redis at ace-redis over TCP (avoids AWX's default
# unix-socket broker so web/task can run as separate rootless containers).
import os

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "awx",
        "USER": "awx",
        "PASSWORD": os.environ.get("AWX_PG_PASSWORD", "awxpass"),
        "HOST": "ace-postgres",
        "PORT": 5432,
    }
}

BROKER_URL = "redis://ace-redis:6379/2"
CACHES = {"default": {"BACKEND": "ansible_base.lib.cache.redis_cache.DABRedisCache", "LOCATION": "redis://ace-redis:6379/3"}}
CHANNEL_LAYERS = {"default": {"BACKEND": "channels_redis.core.RedisChannelLayer", "CONFIG": {"hosts": ["redis://ace-redis:6379/2"], "capacity": 10000, "group_expiry": 157784760}}}

CLUSTER_HOST_ID = "ace-awx"

# SECRET_KEY MUST be set from a conf.d file: defaults.py reads /etc/tower/SECRET_KEY
# only into the *development* dynaconf layer, but awx-manage runs in *production*,
# where it would otherwise be empty. Loading it here lands it in the active env.
with open("/etc/tower/SECRET_KEY") as _f:
    SECRET_KEY = _f.read().strip()

ALLOWED_HOSTS = ["*"]
