# UI date selector rollout

The reusable calendar lives in `static/ui/date-picker.js` and `static/ui/date-picker.css`. Load both with `templates/components/ui_date_picker_assets.html`, then call `UiDatePicker.enhance(input)` (or `UiDatePicker.enhanceAll(root)` for every `[data-ui-date]` input in a section).

The original input stays in the page. Its value remains `YYYY-MM-DD`, and a user choice still fires `input` and `change`, so existing filters and presets keep working. Assigning `input.value` from page script updates the visible label.

The main dashboard (`templates/dashboard.html`, `#md-from-date` and `#md-to-date`) and the pages in sections 1, 2, and 3 use this picker.

The page shell that is served is `horilla_theme/templates/index.html`. It loads the picker and enhances every `[data-ui-date]` input, including inputs inserted by HTMX. `templates/index.html` has the same hook when that shell is not in use. Assigning `.value` still updates the label. `UiDatePicker.destroy(input)` removes the calendar when a control has to become a week or month field again.

Theme templates win over app templates when the template name matches. Where both copies exist, edit the `horilla_theme` file.

## 1. Module dashboards

Done. These use the shared calendar on the From/To pair. Preset buttons are unchanged.

| Page | Template | Inputs |
| --- | --- | --- |
| My Dashboard | `base/templates/base/ess_dashboard.html` | `#essFromDate`, `#essToDate` |
| Attendance | `attendance/templates/attendance/dashboard.html` | `#am-from-date`, `#am-to-date` |
| Leave | `leave/templates/leave/dashboard.html` | `#ld-from-date`, `#ld-to-date` |
| Payroll | `payroll/templates/payroll/dashboard.html` | `#pd-from-date`, `#pd-to-date` |
| Performance (PMS) | `pms/templates/pms/dashboard.html` | `#pm-from-date`, `#pm-to-date` |
| Project | `project/templates/project/dashboard.html` | `#pr-from-date`, `#pr-to-date` |
| Onboarding | `onboarding/templates/onboarding/dashboard.html` | `#on-from-date`, `#on-to-date` |
| Offboarding | `offboarding/templates/offboarding/dashboard.html` | `#ob-from-date`, `#ob-to-date` |
| Asset | `asset/templates/asset/dashboard.html` | `#as-from-date`, `#as-to-date` |
| Helpdesk | `helpdesk/templates/helpdesk/dashboard.html` | `#hd-from-date`, `#hd-to-date` |

Each of those templates also has a short CSS block for `input[type="date"]` inside its period picker. That block can go once the custom trigger is in place.

## 2. Other pages with their own date fields

Done. These fields keep their ids, names, `YYYY-MM-DD` values, and existing change handlers. The attendance day and date-range chart controls use this calendar; weekly and monthly switch back to the browser week and month controls. The hours chart stays a month field.

| Page | Template | Fields |
| --- | --- | --- |
| Attendance monthly summary | `attendance/templates/attendance/monthly_summary/monthly_summary.html` | Filter range `#ms-from-date`, `#ms-to-date` (`from_date`, `to_date`) |
| Monthly summary bulk update | `attendance/templates/attendance/monthly_summary/table_partial.html` | Modal `#ms-bulk-from`, `#ms-bulk-to` |
| Attendance analytics chart | `horilla_theme/templates/attendance/dashboard/dashboard.html` | Day / date-range chart control. The app copy `attendance/templates/attendance/dashboard/dashboard.html` is the same template name and is shadowed. |
| Attendance chart tiles | `horilla_theme/templates/horilla_theme/components/dashboard_tiles.html` | `#attendance_month` |
| Attendance chart script | `attendance/static/dashboard/attendanceChart.js` | Builds `#department_month2` and `#attendance_month2` |
| Work records list | `horilla_theme/templates/attendance/work_record/work_record_list.html` | Date filters |
| Work records view | `horilla_theme/templates/attendance/work_record/work_record_view.html` | `#startDate` and the end date. App copy `attendance/templates/attendance/work_record/work_record_view.html` is shadowed. |
| Payroll contributions | `payroll/templates/payroll/contribution/contribution_home.html` | `#from_date`, `#to_date` |
| Standard report | `horilla_theme/templates/report/standard_report.html` | Custom range `#sr-from`, `#sr-to` |
| Standard report print | `horilla_theme/templates/report/standard_report_print_modal.html` | `#sr-print-from`, `#sr-print-to` |
| Shift roster | `base/templates/base/roster/roster_grid.html` | Bulk `from_date`, `to_date` |
| Publish roster | `base/templates/base/roster/publish_form.html` | `from_date`, `to_date` |
| Roster import | `base/templates/base/roster/roster_import_form.html` | SweetAlert fields `#swal_start`, `#swal_end` (built in script) |
| Employee export | `horilla_theme/templates/employee/export_data_employee.html` | Attendance, leave, and payroll ranges (`attendance_date__gte` / `__lte`, `from_date` / `to_date`, `start_date_from` / `end_date_till`). App copy `employee/templates/employee/export_data_employee.html` is shadowed. |
| Employee picker | `horilla_widgets/templates/horilla_widgets/employee_picker/rail.html` | Joined from / joined till |
| Onboarding candidates | `onboarding/templates/onboarding/candidates.html` and `onboarding/templates/onboarding/group_by.html` | Inline joining date and probation end |
| Onboarding candidate cells | `onboarding/templates/cbv/onboarding_candidates/date_of_joining.html`, `probation_date.html` | Same two dates in the class-based list |
| Start onboarding modal | `horilla_theme/templates/cbv/onboarding_candidates/actions.html` | Joining date and probation end per candidate |
| Offboarding resignations | `offboarding/templates/offboarding/resignation/requests_view.html` | `notice_period_starts`, `notice_period_ends` |
| Offboarding resignation rows | `offboarding/templates/cbv/resignation/resignation.html` | Same notice-period dates, including fields injected from script |
| PMS key result | `pms/views.py` (HTML string around the end-date field) | `#id_end_date` |
| Helpdesk ticket | `horilla_theme/templates/helpdesk/ticket/ticket_detail.html` | Deadline (`name="deadline"`), saved on change |
| Recruitment survey | `recruitment/templates/survey_form.html` | Date question |
| Survey preview | `horilla_theme/templates/survey_preview_form.html` | Date question preview. App copy `recruitment/templates/survey_preview_form.html` is shadowed. |
| Record history | `horilla_theme/templates/tabs/history.html`, `horilla_theme/templates/candidate/history.html` | History `date_from` / `date_to` filters |

Fields added after the first paint are picked up too. HTMX swaps and the PMS end-date response are enhanced from `htmx:afterSwap`. Roster import, resignation, and start-onboarding dialogs enhance when the dialog opens. The attendance chart script enhances the extra date-range input itself.

## 3. Forms and list filters

Done. Date widgets render with `data-ui-date` from `horilla_theme/templates/django/forms/widgets/date.html`. A datetime widget, and a text widget that is shown as a date (employee date of birth), do the same. The page enhances those inputs on load and after HTMX inserts a form or filter. Names, submitted `YYYY-MM-DD` values, and Apply still work as before. Time fields stay time fields.

The “+ Add filter” rows use the same calendar for a date value. Report builders that reuse one box for a date, a time, or plain text keep the browser control, because that box changes type after it is created.

Screens in this group:

| Area | Where it shows up | Date fields |
| --- | --- | --- |
| Employees | Employee form, work info, disciplinary action, employee list filter | Date of birth, joining date, contract end, disciplinary start, probation from/till, not-in-yet / not-out-yet |
| Attendance | Attendance, activity, and request forms; attendance, activity, and late/early filters | Attendance date, clock-in date, clock-out date, and the from/till filters |
| Leave | Leave type, leave request, user leave request, restricted dates, and their filters | Start, end, carry-forward expiry, assigned date, from/to |
| Shift and work type | Shift request, allocation, work-type request, rotating shift/work type, holidays, penalties | Requested date, requested till, start date, holiday range, penalty range |
| Roster filters | Roster list filter | `from_date`, `to_date` |
| Payroll | Contract, payslip, deduction, bonus, loan, reimbursement, pay adjustment, payroll batch, and their filters | Contract range, payslip range, pay date, one-time date, loan dates, period start/end |
| Recruitment | Recruitment, candidate, interview schedule, and candidate/recruitment/interview/skill-zone filters | Start/end, scheduled date, date of birth, joining, probation end, hired date |
| Onboarding | Candidate form and employee creation; pipeline, kanban, and candidate filters | Joining date, date of birth, schedule and probation ranges |
| Performance | Objective, feedback, meeting, and employee-objective filters | Start/end and created/updated ranges, meeting date |
| Project | Project, task, and timesheet forms and filters | Start, end, timesheet date, period from/to |
| Asset | Asset form, return form, history and renewal filters | Purchase date, expiry, return date, assigned date |
| Helpdesk | Ticket form and ticket filter | Deadline, created range, from/to |
| Offboarding | Resignation form and letter, task, and pipeline filters | Notice period start/end, planned leave date, created ranges |
| Meetings | Google meeting filter | From / to |

## 4. Leave these alone

| File | Why |
| --- | --- |
| `static/build/js/pivottable_plot.min.js` | Vendored chart bundle |
| `horilla_theme/static/cdn/orgChart/orgchart.js` | Vendored org chart |
| `payroll/forms/component_forms.py` comment near the payslip widget | Comment only, not a control |
