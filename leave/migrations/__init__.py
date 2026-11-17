"""Leave migrations.

Django imports this package before the leave tables exist. Querying here
raises ProgrammingError on an empty tenant database and aborts the
PostgreSQL transaction that migrate is using. The leave views create the
default EmployeePastLeaveRestrict row when an operator opens that screen.
"""
