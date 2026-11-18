# Pricing catalog

Operators configure plans and add-ons at `/control/plans/`. Amounts are whole Indian rupees, exclusive of GST. The control plane does not calculate tax, proration, or a second currency.

## Billing cycles

Every plan and add-on has three prices, each for one full period:

- Monthly
- Semi-annual (six months)
- Annual (twelve months)

The seeded catalog sets semi-annual to six times the monthly unit and annual to the monthly unit times 12 with the existing 20% discount. After that, each cycle is its own number. Changing one does not recalculate the others.

`quote` in `control/pricing.py` is the only calculator. The plans page, the subscription invoice, and the billing totals all use it.

## What a price change does

Saving a plan or add-on updates the catalog only. A tenant stores `locked_plan_unit`, and each selected add-on stores `locked_unit`, when the subscription is created or the operator saves a new plan, cycle, or add-on set. The next invoice uses those locked units. Issued invoices already store `amount_rupees` and stay as written.

A setup fee is added only to the first invoice, and only when the plan's setup fee is greater than zero.

## Add-ons

An add-on with no compatible plans can be quoted on every plan. Otherwise it can be quoted only on the plans that are checked. A mandatory add-on is included for those plans. Inactive and archived plans, and inactive add-ons, are left out of the quote form.

Seat count is the quantity. A per-seat add-on multiplies its cycle price by that count. There is no separate add-on quantity.

## Trial length

`trial_days` on the plan is how long a new trial runs after activation. Existing plans stay at 14 days.
