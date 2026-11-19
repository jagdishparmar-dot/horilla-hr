"""Phase R0: S3-compatible tenant backup store.

No test here needs boto3 or a real bucket: the client is replaced by an
in-memory stub patched over ``control.backup_store._client``.
"""

import os
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest import mock

from cryptography.fernet import Fernet
from django.core.exceptions import ImproperlyConfigured
from django.test import TestCase, override_settings
from django.utils import timezone

from control import backup_store
from control.backup import (
    backup_dir,
    dump_tenant_database,
    list_dumps,
    prune_backups,
    prune_deleted_tenant_dumps,
    restore_tenant_database,
    retention_victims,
)
from control.backup_store import BackupStoreError, BackupStoreNotConfigured
from control.health import _dump_file_present
from control.models import ProvisionJob, Tenant
from control.provisioning import ProvisionError, _dump_payload

STORE_ENV = {
    "BACKUP_S3_BUCKET": "horilla-backups",
    "BACKUP_S3_ACCESS_KEY": "store-access",
    "BACKUP_S3_SECRET_KEY": "store-secret-value",
}

NO_STORE_ENV = {
    "BACKUP_S3_BUCKET": "",
    "BACKUP_S3_ACCESS_KEY": "",
    "BACKUP_S3_SECRET_KEY": "",
    "BACKUP_S3_PREFIX": "",
}


def _name(moment: datetime) -> str:
    return moment.strftime("%Y%m%dT%H%M%S%fZ") + ".dump"


class _MissingError(Exception):
    """What head/download raise for an absent key, shaped like botocore's."""

    def __init__(self):
        super().__init__("not found")
        self.response = {"Error": {"Code": "404"}}


class _StubClient:
    def __init__(self, objects=None, fail=None):
        self.objects = dict(objects or {})
        self.fail = fail

    def _maybe_fail(self):
        if self.fail is not None:
            raise self.fail

    def upload_file(self, filename, bucket, key):
        self._maybe_fail()
        with open(filename, "rb") as handle:
            self.objects[key] = handle.read()

    def download_file(self, bucket, key, filename):
        self._maybe_fail()
        if key not in self.objects:
            raise _MissingError()
        with open(filename, "wb") as handle:
            handle.write(self.objects[key])

    def head_object(self, Bucket, Key):
        self._maybe_fail()
        if Key not in self.objects:
            raise _MissingError()
        return {
            "ContentLength": len(self.objects[Key]),
            "LastModified": timezone.now(),
        }

    def list_objects_v2(self, Bucket, Prefix, ContinuationToken=None):
        self._maybe_fail()
        keys = sorted(key for key in self.objects if key.startswith(Prefix))
        return {
            "Contents": [
                {
                    "Key": key,
                    "Size": len(self.objects[key]),
                    "LastModified": timezone.now(),
                }
                for key in keys
            ],
            "IsTruncated": False,
        }

    def delete_object(self, Bucket, Key):
        self._maybe_fail()
        self.objects.pop(Key, None)


class StoreModuleTests(TestCase):
    """backup_store alone: configuration, key validation, stub round trips."""

    def test_configured_follows_the_bucket_variable(self):
        with mock.patch.dict(os.environ, NO_STORE_ENV):
            self.assertFalse(backup_store.configured())
            with self.assertRaises(BackupStoreNotConfigured):
                backup_store._client()
        with mock.patch.dict(os.environ, STORE_ENV):
            self.assertTrue(backup_store.configured())

    def test_bucket_without_credentials_refuses_to_build_a_client(self):
        env = dict(STORE_ENV, BACKUP_S3_SECRET_KEY="")
        with mock.patch.dict(os.environ, env):
            with self.assertRaises(ImproperlyConfigured):
                backup_store._client()

    def test_dump_names_are_bare_files_only(self):
        good = _name(datetime(2026, 11, 19, 1, 2, 3))
        self.assertEqual(backup_store.validate_dump_name(good), good)
        for bad in (
            "",
            "a/b.dump",
            "..%2f.dump",
            "../escape.dump",
            ".hidden.dump",
            "nodump.sql",
            "a\\b.dump",
            "sp ace.dump",
        ):
            with self.assertRaises(BackupStoreError, msg=bad):
                backup_store.validate_dump_name(bad)

    def test_keys_are_scoped_to_the_validated_slug(self):
        with mock.patch.dict(os.environ, dict(STORE_ENV, BACKUP_S3_PREFIX="/team/")):
            self.assertEqual(
                backup_store.object_key("acme", "a.dump"),
                "team/backups/acme/a.dump",
            )
        with mock.patch.dict(os.environ, dict(STORE_ENV, BACKUP_S3_PREFIX="")):
            self.assertEqual(
                backup_store.object_key("acme", "a.dump"), "backups/acme/a.dump"
            )
            with self.assertRaises(Exception):
                backup_store.object_key("acme/../beta", "a.dump")

    def test_put_get_head_list_delete_round_trip(self):
        stub = _StubClient()
        folder = backup_dir("acme")
        folder.mkdir(parents=True, exist_ok=True)
        local = folder / _name(datetime(2026, 11, 19, 4, 5, 6))
        local.write_bytes(b"dump-bytes")
        try:
            with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
                "control.backup_store._client", return_value=stub
            ):
                stored = backup_store.put(local, "acme", local.name)
                self.assertEqual(stored["key"], f"backups/acme/{local.name}")
                self.assertEqual(stored["size"], 10)

                info = backup_store.head("acme", local.name)
                self.assertEqual(info["size"], 10)
                self.assertIsNone(backup_store.head("acme", "20200101T000000000000Z.dump"))

                listed = backup_store.list_keys("acme")
                self.assertEqual([entry["name"] for entry in listed], [local.name])
                self.assertEqual(backup_store.list_keys("beta"), [])

                copy = folder / ".copy.dump"
                backup_store.get("acme", local.name, copy)
                self.assertEqual(copy.read_bytes(), b"dump-bytes")
                copy.unlink()

                backup_store.delete("acme", local.name)
                self.assertIsNone(backup_store.head("acme", local.name))
        finally:
            local.unlink(missing_ok=True)

    def test_list_keys_follows_continuation_tokens_and_skips_foreign_names(self):
        pages = [
            {
                "Contents": [
                    {"Key": "backups/acme/20260102T000000000000Z.dump", "Size": 1},
                    {"Key": "backups/acme/.restore-tmp.dump", "Size": 1},
                ],
                "IsTruncated": True,
                "NextContinuationToken": "t2",
            },
            {
                "Contents": [
                    {"Key": "backups/acme/20260101T000000000000Z.dump", "Size": 2},
                    {"Key": "backups/acme/notes.txt", "Size": 3},
                ],
                "IsTruncated": False,
            },
        ]
        stub = _StubClient()
        stub.list_objects_v2 = mock.Mock(side_effect=pages)
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ):
            listed = backup_store.list_keys("acme")
        self.assertEqual(
            [entry["name"] for entry in listed],
            [
                "20260102T000000000000Z.dump",
                "20260101T000000000000Z.dump",
            ],
        )
        self.assertEqual(stub.list_objects_v2.call_count, 2)
        self.assertEqual(
            stub.list_objects_v2.call_args_list[1].kwargs.get("ContinuationToken"),
            "t2",
        )

    def test_store_errors_never_carry_secrets(self):
        stub = _StubClient(fail=RuntimeError("endpoint auth store-secret-value"))
        folder = backup_dir("acme")
        folder.mkdir(parents=True, exist_ok=True)
        local = folder / _name(datetime(2026, 11, 19, 7, 8, 9))
        local.write_bytes(b"x")
        try:
            with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
                "control.backup_store._client", return_value=stub
            ):
                for call in (
                    lambda: backup_store.put(local, "acme", local.name),
                    lambda: backup_store.head("acme", local.name),
                    lambda: backup_store.list_keys("acme"),
                    lambda: backup_store.delete("acme", local.name),
                ):
                    with self.assertRaises(BackupStoreError) as raised:
                        call()
                    message = str(raised.exception)
                    self.assertIn("RuntimeError", message)
                    self.assertNotIn("store-secret-value", message)
        finally:
            local.unlink(missing_ok=True)


class _TenantMixin:
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.addCleanup(self._env.stop)
        self.tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.ACTIVE,
            db_name="tenant_acme",
            db_user="tenant_acme",
            db_host="db",
            db_port=5432,
        )
        self.tenant.set_db_password("db-secret")
        self.tenant.save()

    def _fake_pg_run(self, command, **kwargs):
        if "-f" in command:
            path = command[command.index("-f") + 1]
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as handle:
                handle.write(b"dump")
        return mock.Mock(returncode=0)

    def _clean_folder(self, slug="acme"):
        folder = backup_dir(slug)
        if folder.is_dir():
            for path in folder.iterdir():
                if path.is_file():
                    path.unlink()


class DumpUploadTests(_TenantMixin, TestCase):
    """R0-02: dump_tenant_database spools locally then uploads."""

    def test_store_mode_uploads_and_removes_the_spool_file(self):
        stub = _StubClient()
        self._clean_folder()
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ), mock.patch("shutil.which", return_value="/usr/bin/pg_dump"), mock.patch(
            "control.backup.subprocess.run", side_effect=self._fake_pg_run
        ):
            location = dump_tenant_database(self.tenant)
        self.assertTrue(location.startswith("backups/acme/"))
        self.assertIn(location, stub.objects)
        leftovers = [
            path.name for path in backup_dir("acme").iterdir() if path.is_file()
        ]
        self.assertEqual(leftovers, [])

    def test_upload_failure_fails_the_job_and_keeps_the_spool_file(self):
        stub = _StubClient(fail=RuntimeError("boom store-secret-value"))
        self._clean_folder()
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ), mock.patch("shutil.which", return_value="/usr/bin/pg_dump"), mock.patch(
            "control.backup.subprocess.run", side_effect=self._fake_pg_run
        ):
            with self.assertRaises(ProvisionError) as raised:
                dump_tenant_database(self.tenant)
        message = str(raised.exception)
        self.assertIn("upload failed", message)
        self.assertNotIn("store-secret-value", message)
        kept = [path.name for path in backup_dir("acme").iterdir() if path.is_file()]
        self.assertEqual(len(kept), 1)
        self._clean_folder()

    def test_fallback_mode_still_returns_the_local_path(self):
        self._clean_folder()
        with mock.patch.dict(os.environ, NO_STORE_ENV), mock.patch(
            "shutil.which", return_value="/usr/bin/pg_dump"
        ), mock.patch("control.backup.subprocess.run", side_effect=self._fake_pg_run):
            path = dump_tenant_database(self.tenant)
        self.assertIn("backups/acme/", path.replace("\\", "/"))
        self.assertTrue(os.path.isfile(path))
        os.remove(path)

    def test_delete_with_a_failed_upload_never_drops_the_database(self):
        from control.provisioning import delete_tenant

        stub = _StubClient(fail=RuntimeError("store down"))
        self._clean_folder()
        job = ProvisionJob.objects.create(
            tenant=self.tenant,
            kind=ProvisionJob.Kind.DELETE,
            status=ProvisionJob.Status.RUNNING,
            payload={"confirm_slug": "acme"},
        )
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ), mock.patch("shutil.which", return_value="/usr/bin/pg_dump"), mock.patch(
            "control.backup.subprocess.run", side_effect=self._fake_pg_run
        ), mock.patch(
            "control.provisioning._database_exists", return_value=True
        ), mock.patch(
            "control.provisioning._drop_database_and_role"
        ) as drop:
            with self.assertRaises(ProvisionError):
                delete_tenant(job)
        drop.assert_not_called()
        job.refresh_from_db()
        self.assertEqual(job.step, "dump")
        self.tenant.refresh_from_db()
        self.assertNotEqual(self.tenant.status, Tenant.Status.DELETED)
        self._clean_folder()

    def test_backup_job_payload_names_the_key_or_the_path(self):
        stub = _StubClient({"backups/acme/20261119T000000000000Z.dump": b"12345"})
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ):
            payload = _dump_payload(
                "acme", "backups/acme/20261119T000000000000Z.dump"
            )
        self.assertEqual(
            payload,
            {
                "dump_key": "backups/acme/20261119T000000000000Z.dump",
                "dump_bytes": 5,
            },
        )
        with mock.patch.dict(os.environ, NO_STORE_ENV):
            payload = _dump_payload("acme", "/app/backups/acme/x.dump")
        self.assertEqual(payload, {"dump_path": "/app/backups/acme/x.dump"})


class RestoreFromStoreTests(_TenantMixin, TestCase):
    """R0-03: restore pulls from the store, local folder stays the fallback."""

    def test_restore_downloads_to_a_spool_file_and_removes_it(self):
        name = _name(datetime(2026, 11, 19, 10, 0, 0))
        stub = _StubClient({f"backups/acme/{name}": b"dump-bytes"})
        self._clean_folder()
        captured = {}

        def fake_run(command, **kwargs):
            captured["command"] = command
            captured["spool_exists"] = os.path.isfile(command[-1])
            return mock.Mock(returncode=0)

        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ), mock.patch("shutil.which", return_value="/usr/bin/pg_restore"), mock.patch(
            "control.backup.subprocess.run", side_effect=fake_run
        ):
            restore_tenant_database(self.tenant, name)
        spool = captured["command"][-1].replace("\\", "/")
        self.assertIn("backups/acme/", spool)
        self.assertTrue(captured["spool_exists"])
        leftovers = [
            path.name for path in backup_dir("acme").iterdir() if path.is_file()
        ]
        self.assertEqual(leftovers, [])

    def test_download_failure_removes_the_spool_and_raises(self):
        name = _name(datetime(2026, 11, 19, 10, 0, 0))
        stub = _StubClient({f"backups/acme/{name}": b"dump-bytes"})
        self._clean_folder()

        def fail_download(bucket, key, filename):
            raise RuntimeError("store-secret-value leaked")

        stub.download_file = fail_download
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ), mock.patch("shutil.which", return_value="/usr/bin/pg_restore"):
            with self.assertRaises(ProvisionError) as raised:
                restore_tenant_database(self.tenant, name)
        self.assertNotIn("store-secret-value", str(raised.exception))
        leftovers = [
            path.name for path in backup_dir("acme").iterdir() if path.is_file()
        ]
        self.assertEqual(leftovers, [])

    def test_missing_store_object_falls_back_to_a_local_dump(self):
        stub = _StubClient()
        folder = backup_dir("acme")
        folder.mkdir(parents=True, exist_ok=True)
        local = folder / "sample.dump"
        local.write_bytes(b"old dump")
        captured = {}

        def fake_run(command, **kwargs):
            captured["command"] = command
            return mock.Mock(returncode=0)

        try:
            with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
                "control.backup_store._client", return_value=stub
            ), mock.patch(
                "shutil.which", return_value="/usr/bin/pg_restore"
            ), mock.patch(
                "control.backup.subprocess.run", side_effect=fake_run
            ):
                restore_tenant_database(self.tenant, "sample.dump")
            self.assertEqual(captured["command"][-1], str(local))
        finally:
            local.unlink(missing_ok=True)

    def test_restore_refuses_a_path_shaped_name_before_touching_the_store(self):
        stub = _StubClient()
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ), mock.patch("shutil.which", return_value="/usr/bin/pg_restore"):
            with self.assertRaises(ProvisionError):
                restore_tenant_database(self.tenant, "../beta/steal.dump")


class HealthDumpKeyTests(_TenantMixin, TestCase):
    """R0-04: the health page verifies dumps in the store."""

    def _job(self, payload):
        return SimpleNamespace(payload=payload)

    def test_dump_key_present_in_the_store(self):
        name = "20261119T000000000000Z.dump"
        stub = _StubClient({f"backups/acme/{name}": b"dump"})
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ):
            self.assertTrue(
                _dump_file_present(
                    self.tenant, self._job({"dump_key": f"backups/acme/{name}"})
                )
            )
            self.assertFalse(
                _dump_file_present(
                    self.tenant,
                    self._job({"dump_key": "backups/acme/20200101T000000000000Z.dump"}),
                )
            )
            # Another tenant's key never verifies, even if the object exists.
            stub.objects[f"backups/beta/{name}"] = b"dump"
            self.assertFalse(
                _dump_file_present(
                    self.tenant, self._job({"dump_key": f"backups/beta/{name}"})
                )
            )

    def test_dump_key_with_the_store_off_is_not_verified(self):
        with mock.patch.dict(os.environ, NO_STORE_ENV):
            self.assertFalse(
                _dump_file_present(
                    self.tenant,
                    self._job({"dump_key": "backups/acme/20261119T000000000000Z.dump"}),
                )
            )

    def test_store_errors_read_as_absent(self):
        stub = _StubClient(fail=RuntimeError("down"))
        with mock.patch.dict(os.environ, STORE_ENV), mock.patch(
            "control.backup_store._client", return_value=stub
        ):
            self.assertFalse(
                _dump_file_present(
                    self.tenant,
                    self._job({"dump_key": "backups/acme/20261119T000000000000Z.dump"}),
                )
            )


class RetentionTests(_TenantMixin, TestCase):
    """R0-07: keep the newest dumps plus one per recent week; sweep deleted."""

    def test_retention_keeps_daily_then_weekly_and_spares_foreign_names(self):
        names = [
            _name(datetime(2026, 11, 19)),
            _name(datetime(2026, 11, 18)),
            _name(datetime(2026, 11, 17)),
            _name(datetime(2026, 11, 10)),
            _name(datetime(2026, 11, 3)),
            "sample.dump",
            ".restore-tmp.dump",
        ]
        victims = retention_victims(names, keep_daily=2, keep_weekly=1)
        self.assertEqual(
            victims,
            [_name(datetime(2026, 11, 10)), _name(datetime(2026, 11, 3))],
        )
        self.assertEqual(retention_victims(names, keep_daily=10, keep_weekly=4), [])

    def test_prune_backups_in_local_mode_deletes_victims_only(self):
        folder = backup_dir("acme")
        folder.mkdir(parents=True, exist_ok=True)
        self._clean_folder()
        old = folder / _name(datetime(2026, 1, 1))
        new = folder / _name(datetime(2026, 11, 19))
        hand = folder / "sample.dump"
        for path in (old, new, hand):
            path.write_bytes(b"dump")
        env = dict(NO_STORE_ENV, BACKUP_KEEP_DAILY="1", BACKUP_KEEP_WEEKLY="0")
        try:
            with mock.patch.dict(os.environ, env):
                victims = prune_backups("acme")
            self.assertEqual(victims, [old.name])
            self.assertFalse(old.exists())
            self.assertTrue(new.exists())
            self.assertTrue(hand.exists())
        finally:
            self._clean_folder()

    def test_prune_backups_in_store_mode_deletes_store_objects(self):
        old = _name(datetime(2026, 1, 1))
        new = _name(datetime(2026, 11, 19))
        stub = _StubClient(
            {
                f"backups/acme/{old}": b"1",
                f"backups/acme/{new}": b"2",
                f"backups/beta/{old}": b"3",
            }
        )
        env = dict(STORE_ENV, BACKUP_KEEP_DAILY="1", BACKUP_KEEP_WEEKLY="0")
        with mock.patch.dict(os.environ, env), mock.patch(
            "control.backup_store._client", return_value=stub
        ):
            victims = prune_backups("acme")
        self.assertEqual(victims, [old])
        self.assertNotIn(f"backups/acme/{old}", stub.objects)
        self.assertIn(f"backups/acme/{new}", stub.objects)
        self.assertIn(f"backups/beta/{old}", stub.objects)

    def test_deleted_tenant_dumps_are_swept_after_thirty_days(self):
        now = timezone.now()
        gone = Tenant.objects.create(
            name="Gone",
            slug="goneco",
            status=Tenant.Status.DELETED,
            deleted_at=now - timedelta(days=31),
        )
        fresh = Tenant.objects.create(
            name="Fresh",
            slug="freshco",
            status=Tenant.Status.DELETED,
            deleted_at=now - timedelta(days=5),
        )
        for tenant in (gone, fresh):
            folder = backup_dir(tenant.slug)
            folder.mkdir(parents=True, exist_ok=True)
            (folder / _name(datetime(2026, 10, 1))).write_bytes(b"dump")
        try:
            with mock.patch.dict(os.environ, NO_STORE_ENV):
                removed = prune_deleted_tenant_dumps(now=now)
            self.assertEqual(removed, 1)
            self.assertEqual(list_dumps("goneco"), [])
            self.assertEqual(len(list_dumps("freshco")), 1)
        finally:
            self._clean_folder("goneco")
            self._clean_folder("freshco")

    def test_one_store_failure_does_not_stop_the_sweep(self):
        now = timezone.now()
        for slug in ("aaaco", "bbbco"):
            Tenant.objects.create(
                name=slug,
                slug=slug,
                status=Tenant.Status.DELETED,
                deleted_at=now - timedelta(days=40),
            )
        calls = []

        def flaky(slug):
            calls.append(slug)
            if slug == "aaaco":
                raise BackupStoreError("Backup store list failed: RuntimeError")
            return [{"name": _name(datetime(2026, 10, 1)), "size": 1}]

        with mock.patch("control.backup.list_dumps", side_effect=flaky), mock.patch(
            "control.backup._delete_dump"
        ) as deleter:
            removed = prune_deleted_tenant_dumps(now=now)
        self.assertEqual(removed, 1)
        self.assertEqual(sorted(calls), ["aaaco", "bbbco"])
        deleter.assert_called_once()


@override_settings(HORILLA_MULTITENANT=True)
class NightlyCoverageTests(TestCase):
    """R0-06: the nightly run covers every status whose database holds data."""

    def test_backup_postgres_enqueues_data_holding_tenants_only(self):
        from pg_backup.scheduler import backup_postgres

        expected = set()
        for slug, status in (
            ("activeco", Tenant.Status.ACTIVE),
            ("trialco", Tenant.Status.TRIALING),
            ("dueco", Tenant.Status.PAST_DUE),
            ("heldco", Tenant.Status.SUSPENDED),
            ("newco", Tenant.Status.PROVISIONING),
            ("brokeco", Tenant.Status.FAILED),
            ("byeco", Tenant.Status.DELETED),
        ):
            Tenant.objects.create(name=slug, slug=slug, status=status)
            if status in (
                Tenant.Status.ACTIVE,
                Tenant.Status.TRIALING,
                Tenant.Status.PAST_DUE,
                Tenant.Status.SUSPENDED,
            ):
                expected.add(slug)
        with mock.patch("control.provisioning.enqueue_backup") as enqueue:
            backup_postgres()
        slugs = {call.args[0].slug for call in enqueue.call_args_list}
        self.assertEqual(slugs, expected)


class ProvisionerSweepTests(TestCase):
    """R0-07: the worker sweep is time-gated and never raises."""

    def test_sweep_runs_once_then_waits_out_the_gate(self):
        from control.management.commands import run_provisioner as command

        with mock.patch.object(command, "_next_sweep", 0.0):
            with mock.patch(
                "control.backup.prune_deleted_tenant_dumps", return_value=3
            ) as prune:
                self.assertEqual(command._sweep_deleted_dumps(), 3)
                self.assertEqual(command._sweep_deleted_dumps(), 0)
            self.assertEqual(prune.call_count, 1)
            with mock.patch(
                "control.backup.prune_deleted_tenant_dumps",
                side_effect=RuntimeError("down"),
            ):
                self.assertEqual(command._sweep_deleted_dumps(force=True), 0)
