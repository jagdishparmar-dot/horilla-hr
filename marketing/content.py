"""Copy for the public site, kept apart from the views and templates.

Structure and feature descriptions follow the Horilla product story. Anything
that is a Horilla fact rather than a ClockMe one (customer counts, star counts,
testimonials, its own price list) is deliberately absent. Prices are never
written here; the pricing pages read them from the plan catalog.
"""

# The nine modules, in the order the product presents them.
MODULES = (
    {
        "key": "attendance",
        "icon": "clock",
        "name": "Attendance",
        "summary": "Biometric, geo-fenced, and mobile check-in. Every punch flows into payroll automatically.",
        "detail": "Stop reconciling logs by hand. Punches from biometric devices, the mobile app, and the web all land in one record, ready for payroll.",
        "points": (
            "Biometric, mobile, and web check-in",
            "Geo-fenced entries and office network restriction",
            "Late-come and early-out tracking",
            "Attendance requests and regularisation",
        ),
    },
    {
        "key": "payroll",
        "icon": "payroll",
        "name": "Payroll",
        "summary": "Overtime, deductions, and statutory filings calculated from live attendance.",
        "detail": "Payroll reads attendance and leave directly, so a pay run is a review of finished numbers rather than a rebuild from spreadsheets.",
        "points": (
            "Overtime and leave pulled from live attendance",
            "Allowances, deductions, and reimbursements",
            "Configurable tax rules and statutory components",
            "Payslips employees download themselves",
        ),
    },
    {
        "key": "leave",
        "icon": "calendar",
        "name": "Leave",
        "summary": "Employees apply on mobile. Managers approve in one tap. Balances update in real time.",
        "detail": "One request, one approval, one balance. No inbox ping-pong between employee, manager, and HR.",
        "points": (
            "Leave types, balances, and accrual rules",
            "Requests and approvals from mobile",
            "Holiday and company leave calendars",
            "Balances that update the moment a request is approved",
        ),
    },
    {
        "key": "recruitment",
        "icon": "recruitment",
        "name": "Recruitment",
        "summary": "Job postings, applicant tracking, and interview scheduling: the full pipeline from JD to offer.",
        "detail": "Every recruiter step lives in one pipeline, and a candidate who accepts moves straight into onboarding.",
        "points": (
            "Job openings and applicant tracking",
            "Pipeline stages from application to offer",
            "Interview scheduling",
            "Candidate ratings and feedback",
        ),
    },
    {
        "key": "onboarding",
        "icon": "onboarding",
        "name": "Onboarding",
        "summary": "Automated checklists, document collection, and access provisioning, so people are live on day one.",
        "detail": "A new hire triggers a chain of tasks that are tracked until they are done. Offboarding closes the loop when someone leaves.",
        "points": (
            "Automated checklists for every new hire",
            "Document collection and acknowledgement",
            "Task ownership across HR, IT, and managers",
            "Offboarding for exits in the same workspace",
        ),
    },
    {
        "key": "performance",
        "icon": "target",
        "name": "Performance",
        "summary": "Goals, OKRs, 360° reviews, and appraisal cycles, structured and on schedule.",
        "detail": "Goals, self-evaluations, and manager feedback share one place, so a review cycle ends when it should.",
        "points": (
            "Goals and OKRs with progress tracking",
            "360° feedback and appraisal cycles",
            "Review cycles that stay on schedule",
            "A history of past reviews per employee",
        ),
    },
    {
        "key": "assets",
        "icon": "assets",
        "name": "Assets",
        "summary": "Track laptops, devices, and equipment assigned to employees, with full lifecycle history.",
        "detail": "Know who holds what, when it was handed over, and when it came back.",
        "points": (
            "Laptops, devices, and equipment in one register",
            "Assign and recover with a full history",
            "Asset requests from employees",
            "Hand-back checks at offboarding",
        ),
    },
    {
        "key": "employees",
        "icon": "employees",
        "name": "Employees",
        "summary": "A single source of truth for every employee: profile, documents, history, and org structure.",
        "detail": "The record every other module reads from. Update it once and attendance, payroll, and leave all agree.",
        "points": (
            "Profile, work information, and documents",
            "Org structure and reporting lines",
            "Bank and contact details",
            "A full history of changes",
        ),
    },
    {
        "key": "helpdesk",
        "icon": "helpdesk",
        "name": "Helpdesk",
        "summary": "HR ticketing built in. Employees raise requests, HR resolves them, and everyone stays informed.",
        "detail": "Questions stop living in DMs. Each request has an owner, a status, and a trail.",
        "points": (
            "Employees raise tickets, HR resolves them",
            "FAQs for the questions that repeat",
            "Notifications at every step",
            "A record of every resolution",
        ),
    },
)

PROBLEMS = (
    {
        "title": "Attendance lives in five spreadsheets",
        "body": "Every Monday, someone spends hours reconciling biometric logs, Excel exports, and email approvals just to work out who showed up last week.",
    },
    {
        "title": "Payroll day is a monthly panic",
        "body": "Overtime miscalculations. Missed deductions. Wrong leave balances. Finance dreads it, and employees lose trust.",
    },
    {
        "title": "Leave approvals clog every inbox",
        "body": "Employee emails manager. Manager emails HR. HR checks a sheet. HR emails back. All for a single leave request.",
    },
    {
        "title": "Performance reviews drag on for months",
        "body": "Goals in one tool, self-evaluations in another, manager feedback in DMs. By the time the cycle ends, half the team has forgotten what they did.",
    },
    {
        "title": "New hires wait weeks to start",
        "body": "Contracts in a shared drive. Laptops in a ticket. Access in IT. Payroll in Excel. Every delay costs real money.",
    },
    {
        "title": "Compliance is a quarterly dread",
        "body": "Tax filings, statutory deductions, audit trails, and policy renewals. When it is all manual, one missed deadline costs more than a year of software.",
    },
)

# "From hire to retire" tiles. ``size`` picks the grid span.
BENTO = (
    {
        "icon": "payroll",
        "size": "third",
        "title": "Payroll that calculates itself",
        "body": "Overtime, leave, and deductions are pulled from live attendance data, so a payroll run is a review, not a rebuild.",
    },
    {
        "icon": "clock",
        "size": "third",
        "title": "Attendance without the spreadsheet",
        "body": "Biometric integrations, mobile check-in, and geo-fenced entries. Every punch flows into payroll in real time.",
    },
    {
        "icon": "zap",
        "size": "third",
        "title": "Approvals in one tap, not ten emails",
        "body": "Employees apply on mobile. Managers approve in one tap. Balances update live, with no chasing on chat.",
    },
    {
        "icon": "employees",
        "size": "half",
        "title": "Self-service for employees, control for HR",
        "body": "Employees manage their own leave, payslips, and documents. HR keeps full visibility without being the middleman for everything.",
    },
    {
        "icon": "shield",
        "size": "half",
        "title": "Compliance baked in, not bolted on",
        "body": "Configurable tax rules, statutory deductions, and labour-law reports adapt to your country's payroll framework, with audit-ready outputs close at hand.",
    },
)

TOUR = (
    {
        "key": "payroll",
        "label": "Payroll",
        "title": "A payroll run you can read at a glance",
        "body": "Attendance and leave feed the pay run, so each line already carries its overtime and deductions. Review, approve, and release payslips.",
        "points": (
            "Gross, deductions, and net in one table",
            "Overtime and leave applied from attendance",
            "Approve the run, then release payslips",
        ),
    },
    {
        "key": "employee",
        "label": "Employee self-service",
        "title": "Employees answer their own questions",
        "body": "Payslips, leave balances, and documents sit in the employee's own portal, which is where HR's inbox finally goes quiet.",
        "points": (
            "Leave balances at a glance",
            "Payslips available to download",
            "Requests raised without emailing HR",
        ),
    },
    {
        "key": "performance",
        "label": "Performance & OKRs",
        "title": "Goals that people actually update",
        "body": "Objectives, progress, and review cycles share one view, so the conversation starts from facts instead of memory.",
        "points": (
            "Objectives with live progress",
            "Review cycles tracked to completion",
            "Self and manager reviews side by side",
        ),
    },
    {
        "key": "helpdesk",
        "label": "Helpdesk",
        "title": "Every request has an owner",
        "body": "Employees raise a request, HR picks it up, and the status is visible to both. Nothing disappears into a DM.",
        "points": (
            "One queue for every HR request",
            "Priority and status on each ticket",
            "A trail from first message to resolution",
        ),
    },
)

AUTOMATIONS = (
    {
        "icon": "calendar",
        "title": "Auto-approve leave and attendance",
        "body": "Set your policies once. ClockMe enforces them automatically, with no manager ping-pong for routine approvals.",
    },
    {
        "icon": "payroll",
        "title": "Payroll calculated automatically",
        "body": "Attendance data flows into payroll. Deductions, overtime, and tax rules are applied every cycle.",
    },
    {
        "icon": "onboarding",
        "title": "Onboarding checklists run themselves",
        "body": "A new hire triggers a chain of tasks: IT provisioning, document signing, and policy acknowledgement, all tracked.",
    },
    {
        "icon": "bell",
        "title": "Smart alerts and compliance reminders",
        "body": "Contract expirations, probation reviews, and document renewals surface before they become problems.",
    },
)

OUTCOMES = (
    {
        "icon": "clock",
        "title": "Less HR admin, every week",
        "body": "Attendance, payroll, leave, and compliance reports that used to take days run from one place, with no copy-paste between tools.",
    },
    {
        "icon": "file",
        "title": "Payroll you can trace",
        "body": "When attendance flows straight into payroll, manual errors have fewer places to hide, and each figure leads back to the record it came from.",
    },
    {
        "icon": "recruitment",
        "title": "Hire faster, onboard in hours",
        "body": "From job posting to signed offer, every recruiter step lives in one pipeline, and onboarding tasks begin when a candidate accepts.",
    },
    {
        "icon": "employees",
        "title": "Employees self-serve, HR stops chasing",
        "body": "Payslips, leave balances, attendance regularisation, and asset requests are one click away in the employee's own portal.",
    },
    {
        "icon": "layers",
        "title": "One record, every module",
        "body": "Attendance, leave, payroll, and reviews read from the same employee record, so a change made once is true everywhere.",
    },
    {
        "icon": "globe",
        "title": "Built to grow with you",
        "body": "Multi-company and multi-language support mean the workspace that fits a small team keeps fitting as you add entities and offices.",
    },
)

SEGMENTS = (
    {
        "range": "10 to 100 employees",
        "name": "Growing startups and SMBs",
        "body": "You need HR that works today, not a three-month implementation project. ClockMe is ready with sensible defaults.",
        "points": (
            "Up and running quickly",
            "Priced per active employee, so cost follows your headcount",
            "Employee self-service from day one",
            "Payroll, leave, and attendance in one place",
        ),
    },
    {
        "range": "100 to 500 employees",
        "name": "Mid-market teams",
        "body": "You have outgrown spreadsheets and basic tools. You need configurable workflows, multi-level approvals, and real reporting.",
        "points": (
            "Approval chains and policies you configure",
            "Performance and goal management",
            "Reports across modules",
            "Recruitment pipeline views",
        ),
    },
    {
        "range": "500+ employees",
        "name": "Enterprises and multi-entity",
        "body": "You need directory sign-in, several entities under one roof, and payroll rules that match how you actually pay.",
        "points": (
            "LDAP and Active Directory sign-in",
            "Multi-company support",
            "Custom payroll rules and tax configuration",
            "Priority SLA and compliance vault add-ons",
        ),
    },
)

# The store apps are not published yet, so nothing here links to a store.
MOBILE_POINTS = (
    "Check in and out from your phone, with geofencing when your admin turns it on",
    "Apply for leave and follow the request",
    "Managers approve in one tap",
    "Biometric app lock on the device",
)

STEPS = (
    {
        "title": "Request your workspace",
        "body": "Tell us your company name, work email, and the address you want. It takes a minute.",
    },
    {
        "title": "We set it up",
        "body": "Our team sets up your workspace and sends your admin the first sign-in details.",
    },
    {
        "title": "Add your people, set your policies",
        "body": "Import employees from a spreadsheet, then configure leave types, overtime, payroll schedule, and approval flows once.",
    },
    {
        "title": "Run your first payroll",
        "body": "Review, approve, and download payslips. Most teams are live before the first cycle closes.",
    },
)

# Beyond the nine modules.
PLATFORM = (
    {
        "icon": "phone",
        "title": "Mobile app, coming soon",
        "body": "Android and iOS apps to check in, apply for leave, and approve requests from a phone.",
    },
    {
        "icon": "chart",
        "title": "Reports and exports",
        "body": "Standard reports across modules, with scheduled delivery to the people who need them.",
    },
    {
        "icon": "lock",
        "title": "Two-factor and lockouts",
        "body": "Two-factor sign-in and automatic lockout after repeated failed attempts.",
    },
    {
        "icon": "layers",
        "title": "Multi-company",
        "body": "Run several companies or branches in one workspace, each with its own policies.",
    },
    {
        "icon": "employees",
        "title": "Directory sign-in",
        "body": "Connect LDAP or Active Directory so people sign in with the account they already have.",
    },
    {
        "icon": "file",
        "title": "Audit trail",
        "body": "Changes to records are recorded, so you can see who changed what, and when.",
    },
)

FAQS = (
    {
        "q": "How do I get a workspace?",
        "a": "Send a request from this site. Our team reviews it, sets up your workspace, and sends your admin the first sign-in details. Nothing is live until that is done.",
        "topics": ("home",),
    },
    {
        "q": "We are HR people, not IT people. Is this complicated?",
        "a": "ClockMe runs as a hosted service, so there are no servers, backups, or upgrades for your team to look after. Your admin signs in, adds people, and sets policies once.",
        "topics": ("home",),
    },
    {
        "q": "Does it work for our country's payroll rules?",
        "a": "The payroll engine is rule driven: tax brackets, statutory deductions, contribution rates, and report formats are all configurable. Add-ons such as multi-state payroll tax filing cover wider setups.",
        "topics": ("home", "pricing"),
    },
    {
        "q": "What does it cost?",
        "a": "Plans are billed monthly, per active employee, exclusive of GST. The pricing page shows the current rates. Larger plans are quoted by our sales team, so use Talk to Sales on those.",
        "topics": ("home", "pricing"),
    },
    {
        "q": "Is there a trial?",
        "a": "Plans come with a trial period. The length is shown on each plan on the pricing page.",
        "topics": ("home", "pricing"),
    },
    {
        "q": "What if we outgrow our plan?",
        "a": "Each plan has an employee cap. When you near it, ask us to move you to a larger plan. Your data and history stay where they are.",
        "topics": ("home", "pricing"),
    },
    {
        "q": "Is our employee data safe?",
        "a": "Sign-in is protected, repeated failed attempts are locked out, and two-factor sign-in is available. Our team looks after hosting, upgrades, and backups.",
        "topics": ("home",),
    },
    {
        "q": "How do we move over from spreadsheets or another system?",
        "a": "Employee records can be imported from Excel or CSV files. Tell us what you use today in your request so we can plan the move with you.",
        "topics": ("home", "pricing"),
    },
    {
        "q": "We have been burned by software before.",
        "a": "Start with the trial period and ask your questions in the request. The amounts on the pricing page are the amounts you pay, exclusive of GST.",
        "topics": ("home",),
    },
)


def faqs_for(topic: str):
    return [item for item in FAQS if topic in item["topics"]]
