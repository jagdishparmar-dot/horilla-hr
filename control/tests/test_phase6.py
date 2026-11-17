from pathlib import Path

from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase

from horilla.settings.security import validate_production_secrets

ROOT = Path(__file__).resolve().parents[2]


class DeployHostTests(SimpleTestCase):
    def test_production_refuses_an_empty_control_url(self):
        with self.assertRaises(ImproperlyConfigured):
            validate_production_secrets("a-real-secret-key", ["hr.example.com"], "unique-init", "")
        validate_production_secrets(
            "a-real-secret-key",
            ["hr.example.com"],
            "unique-init",
            "postgres://horilla_user:secret@db:5432/horilla_db",
        )

    def test_compose_shares_one_control_url_and_probes_that_database(self):
        compose = (ROOT / "docker-compose.yml").read_text(encoding="utf-8")
        prod = (ROOT / "docker-compose.prod.yml").read_text(encoding="utf-8")
        self.assertIn("&control_database_url DATABASE_URL=", compose)
        self.assertIn("- *control_database_url", compose)
        self.assertEqual(prod.count("${DATABASE_URL:?Set DATABASE_URL in .env}"), 2)
        self.assertIn("pg_isready -U", compose)
        self.assertIn("$$POSTGRES_USER", compose)
        self.assertIn("$$POSTGRES_DB", compose)
        self.assertIn("condition: service_healthy", compose)
        self.assertIn("127.0.0.1:8000:8000", prod)
        self.assertIn("POSTGRES_DB: ${POSTGRES_DB:-horilla_control}", prod)
        self.assertNotIn("TENANT_DATABASE_URL", compose)
        self.assertNotIn("TENANT_DATABASE_URL", prod)
        init_sql = (ROOT / "docker" / "postgres" / "init-control.sql").read_text(
            encoding="utf-8"
        )
        self.assertIn("REVOKE CONNECT ON DATABASE", init_sql)
        self.assertIn("FROM PUBLIC", init_sql)

    def test_nginx_names_the_platform_hosts_and_keeps_the_host_header(self):
        nginx = (ROOT / "docker" / "nginx.conf").read_text(encoding="utf-8")
        self.assertIn(
            "server_name ${HORILLA_PLATFORM_DOMAIN} *.${HORILLA_PLATFORM_DOMAIN} manage.${HORILLA_PLATFORM_DOMAIN};",
            nginx,
        )
        self.assertEqual(nginx.count("proxy_set_header Host $host;"), 2)

    def test_release_migrates_control_then_tenants_from_web_only(self):
        entry = (ROOT / "docker" / "entrypoint.sh").read_text(encoding="utf-8")
        lock_at = entry.index("python manage.py lock_control_connect")
        migrate_at = entry.index("python manage.py migrate --noinput")
        tenants_at = entry.index("python manage.py migrate_tenants")
        skip_at = entry.index('HORILLA_SKIP_RELEASE_TASKS:-0}" = "1"')
        self.assertLess(skip_at, lock_at)
        self.assertLess(lock_at, migrate_at)
        self.assertLess(migrate_at, tenants_at)
        compose = (ROOT / "docker-compose.yml").read_text(encoding="utf-8")
        self.assertIn("HORILLA_SKIP_RELEASE_TASKS=1", compose)
        scheduler = compose.split("command: python manage.py run_scheduler", 1)[1]
        scheduler = scheduler.split("image: postgres", 1)[0]
        self.assertIn("web:", scheduler)
        self.assertIn("condition: service_healthy", scheduler)
