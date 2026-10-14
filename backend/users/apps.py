from django.apps import AppConfig


def _configure_sqlite(connection, **kwargs) -> None:
    if connection.vendor != 'sqlite':
        return
    with connection.cursor() as cursor:
        cursor.execute('PRAGMA journal_mode=WAL;')
        cursor.execute('PRAGMA synchronous=NORMAL;')
        cursor.execute('PRAGMA busy_timeout=30000;')


class UsersConfig(AppConfig):
    name = 'users'

    def ready(self) -> None:
        from django.db.backends.signals import connection_created

        connection_created.connect(_configure_sqlite, dispatch_uid='mindsync_sqlite_wal')
        import users.signals  # noqa: F401
