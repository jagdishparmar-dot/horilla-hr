"""Keep the Django test database between runs.

Creating ``test_horilla_db`` replays the full Horilla migration set and takes
several minutes. ``manage.py test`` preserves that database unless
``HORILLA_TEST_KEEPDB=0`` is set for that command.
"""

import os

from django.test.runner import DiscoverRunner


class PreservingDiscoverRunner(DiscoverRunner):
    def __init__(self, *args, keepdb=False, **kwargs):
        if os.environ.get("HORILLA_TEST_KEEPDB", "1") != "0":
            keepdb = True
        super().__init__(*args, keepdb=keepdb, **kwargs)
