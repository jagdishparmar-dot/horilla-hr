/* Reusable date picker.
   Keep the original input (id, name, YYYY-MM-DD value, change/input events)
   and show this calendar instead of the browser date control.

   UiDatePicker.enhance(input, {
     placeholder: 'From',
     firstDay: 1,          // 0 = Sunday
     todayLabel: 'Today',
     clearLabel: 'Clear',
     allowClear: true,
   });
   UiDatePicker.destroy(input) restores the original control.
   Week, month, time, and datetime-local inputs are left alone.
*/
(function (global) {
    'use strict';

    var valueProp = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    var openPicker = null;
    var trackedInputs = [];
    var removalObserver = null;

    function trackInput(input) {
        trackedInputs.push(input);
        if (removalObserver) return;
        removalObserver = new MutationObserver(function () {
            for (var i = trackedInputs.length - 1; i >= 0; i -= 1) {
                var el = trackedInputs[i];
                if (el.isConnected) continue;
                trackedInputs.splice(i, 1);
                if (typeof el._uiDateCleanup === 'function') el._uiDateCleanup();
            }
            if (!trackedInputs.length && removalObserver) {
                removalObserver.disconnect();
                removalObserver = null;
            }
        });
        removalObserver.observe(document.documentElement, { childList: true, subtree: true });
    }

    function untrackInput(input) {
        for (var i = trackedInputs.length - 1; i >= 0; i -= 1) {
            if (trackedInputs[i] === input) trackedInputs.splice(i, 1);
        }
        delete input._uiDateCleanup;
    }

    function destroy(input) {
        if (!(input instanceof HTMLInputElement)) return;
        var api = input._uiDatePicker;
        untrackInput(input);
        if (api && typeof api.close === 'function') api.close();
        if (api && api._pop && api._pop.parentNode) api._pop.parentNode.removeChild(api._pop);
        var wrap = input.closest ? input.closest('.ui-date') : null;
        if (wrap && wrap.parentNode) {
            wrap.parentNode.insertBefore(input, wrap);
            wrap.parentNode.removeChild(wrap);
        }
        input.classList.remove('ui-date__native');
        input.readOnly = false;
        if (input.getAttribute('tabindex') === '-1') input.removeAttribute('tabindex');
        input.removeAttribute('inputmode');
        delete input.dataset.uiDateBound;
        try {
            delete input.value;
        } catch (err) {
            /* Keep the instance accessor if this browser refuses the delete. */
        }
        delete input._uiDatePicker;
    }

    var FORMATTERS = {
        'DD/MM/YY': function (p) { return p.dd + '/' + p.mm + '/' + p.yy; },
        'DD-MM-YYYY': function (p) { return p.dd + '-' + p.mm + '-' + p.yyyy; },
        'DD.MM.YYYY': function (p) { return p.dd + '.' + p.mm + '.' + p.yyyy; },
        'DD/MM/YYYY': function (p) { return p.dd + '/' + p.mm + '/' + p.yyyy; },
        'MM/DD/YYYY': function (p) { return p.mm + '/' + p.dd + '/' + p.yyyy; },
        'YYYY-MM-DD': function (p) { return p.iso; },
        'YYYY/MM/DD': function (p) { return p.yyyy + '/' + p.mm + '/' + p.dd; },
        'MMMM D, YYYY': function (p) { return p.monthLong + ' ' + p.d + ', ' + p.yyyy; },
        'DD MMMM, YYYY': function (p) { return p.dd + ' ' + p.monthLong + ', ' + p.yyyy; },
        'MMM. D, YYYY': function (p) { return p.monthShort + '. ' + p.d + ', ' + p.yyyy; },
        'D MMM. YYYY': function (p) { return p.d + ' ' + p.monthShort + '. ' + p.yyyy; },
        'dddd, MMMM D, YYYY': function (p) { return p.weekday + ', ' + p.monthLong + ' ' + p.d + ', ' + p.yyyy; },
    };

    function pad(n) {
        return String(n).padStart(2, '0');
    }

    function esc(value) {
        return String(value == null ? '' : value).replace(/[&<>"']/g, function (ch) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
        });
    }

    function locale() {
        return document.documentElement.lang || global.CURRENT_LANGUAGE || undefined;
    }

    function parseIso(iso) {
        if (!iso || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return null;
        var parts = iso.split('-');
        var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        if (date.getFullYear() !== Number(parts[0]) || date.getMonth() !== Number(parts[1]) - 1) return null;
        return date;
    }

    function toIso(date) {
        return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate());
    }

    function todayIso() {
        return toIso(new Date());
    }

    function storedFormat() {
        try {
            return localStorage.getItem('selectedDateFormat') || 'MMM. D, YYYY';
        } catch (err) {
            return 'MMM. D, YYYY';
        }
    }

    function formatIso(iso, format) {
        var date = parseIso(iso);
        if (!date) return '';
        var loc = locale();
        var monthShort = date.toLocaleDateString(loc, { month: 'short' }).replace(/\.$/, '');
        var parts = {
            iso: iso,
            d: date.getDate(),
            dd: pad(date.getDate()),
            mm: pad(date.getMonth() + 1),
            yy: String(date.getFullYear()).slice(-2),
            yyyy: String(date.getFullYear()),
            monthShort: monthShort,
            monthLong: date.toLocaleDateString(loc, { month: 'long' }),
            weekday: date.toLocaleDateString(loc, { weekday: 'long' }),
        };
        var formatter = FORMATTERS[format] || FORMATTERS['MMM. D, YYYY'];
        return formatter(parts);
    }

    function weekdayLabels(firstDay) {
        var labels = [];
        var base = new Date(2024, 0, 7);
        for (var i = 0; i < 7; i += 1) {
            var date = new Date(base.getFullYear(), base.getMonth(), base.getDate() + ((i + firstDay) % 7));
            labels.push(date.toLocaleDateString(locale(), { weekday: 'short' }));
        }
        return labels;
    }

    function monthTitle(year, month) {
        return new Date(year, month, 1).toLocaleDateString(locale(), { month: 'long', year: 'numeric' });
    }

    function icon(path) {
        return '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + path + '</svg>';
    }

    var ICONS = {
        calendar: icon('<rect x="3" y="4" width="18" height="18" rx="2"></rect><path d="M16 2v4M8 2v4M3 10h18"></path>'),
        chevL: icon('<path d="M15 18l-6-6 6-6"></path>'),
        chevR: icon('<path d="M9 18l6-6-6-6"></path>'),
        chevsL: icon('<path d="M17 18l-6-6 6-6M11 18l-6-6 6-6"></path>'),
        chevsR: icon('<path d="M7 18l6-6-6-6M13 18l6-6-6-6"></path>'),
    };

    function enhance(input, options) {
        if (!(input instanceof HTMLInputElement)) return null;
        var nativeType = (input.getAttribute('type') || '').toLowerCase();
        if (nativeType === 'week' || nativeType === 'month' || nativeType === 'datetime-local' || nativeType === 'time') {
            if (input.dataset.uiDateBound === '1') destroy(input);
            return null;
        }
        if (input.dataset.uiDateBound === '1') return input._uiDatePicker || null;

        options = options || {};
        var firstDay = Number(options.firstDay);
        if (!Number.isFinite(firstDay)) firstDay = Number(input.dataset.firstDay);
        if (!Number.isFinite(firstDay)) firstDay = 1;
        firstDay = ((firstDay % 7) + 7) % 7;

        if (!input.dataset.firstDay) input.dataset.firstDay = String(firstDay);

        var placeholder = options.placeholder || input.dataset.placeholder || input.getAttribute('placeholder') || '';
        var todayLabel = options.todayLabel || input.dataset.todayLabel || 'Today';
        var clearLabel = options.clearLabel || input.dataset.clearLabel || 'Clear';
        var allowClear = options.allowClear !== false && input.dataset.allowClear !== 'false';

        input.dataset.uiDateBound = '1';
        input.type = 'text';
        input.autocomplete = 'off';
        input.readOnly = true;
        input.tabIndex = -1;
        input.setAttribute('inputmode', 'none');

        var declaredWidth = (input.style.width || '').trim();
        var wrap = document.createElement('span');
        wrap.className = 'ui-date';
        if (input.classList.contains('w-100') || input.classList.contains('w-full') || input.classList.contains('ep-input') || declaredWidth === '100%') {
            wrap.classList.add('ui-date--fill');
        }
        input.parentNode.insertBefore(wrap, input);
        wrap.appendChild(input);
        input.classList.add('ui-date__native');

        var trigger = document.createElement('button');
        trigger.type = 'button';
        trigger.className = 'ui-date__trigger';
        trigger.innerHTML = '<span class="ui-date__value"></span><span class="ui-date__icon">' + ICONS.calendar + '</span>';
        if (input.classList.contains('w-40')) {
            trigger.style.width = '10rem';
            trigger.style.maxWidth = 'none';
            trigger.style.minWidth = '0';
        } else if (declaredWidth && declaredWidth !== '100%' && declaredWidth !== 'auto') {
            trigger.style.width = declaredWidth;
            trigger.style.maxWidth = 'none';
            trigger.style.minWidth = '0';
        }
        if (input.style.height) trigger.style.height = input.style.height;
        wrap.appendChild(trigger);
        var valueEl = trigger.querySelector('.ui-date__value');

        var pop = document.createElement('div');
        pop.className = 'ui-date__pop';
        pop.hidden = true;
        pop.setAttribute('role', 'dialog');
        pop.setAttribute('aria-modal', 'false');
        pop.setAttribute('aria-label', input.getAttribute('title') || placeholder || 'Choose date');
        var host = (input.closest && input.closest('.swal2-popup')) || document.body;
        host.appendChild(pop);

        var viewYear = new Date().getFullYear();
        var viewMonth = new Date().getMonth();

        function read() {
            return valueProp.get.call(input);
        }

        function write(next) {
            valueProp.set.call(input, next == null ? '' : String(next));
        }

        function inRange(iso) {
            if (!iso) return true;
            var min = input.min || input.getAttribute('min') || '';
            var max = input.max || input.getAttribute('max') || '';
            if (min && iso < min) return false;
            if (max && iso > max) return false;
            return true;
        }

        function paint() {
            var iso = read();
            var label = iso ? formatIso(iso, storedFormat()) : '';
            valueEl.textContent = label || placeholder || 'Select date';
            valueEl.classList.toggle('ui-date__value--empty', !label);
            var name = input.getAttribute('title') || placeholder || 'Date';
            trigger.setAttribute('aria-label', label ? name + ': ' + label : name);
            trigger.title = label || input.getAttribute('title') || placeholder || '';
            trigger.disabled = input.disabled;
        }

        function close() {
            if (pop.hidden) return;
            pop.hidden = true;
            wrap.classList.remove('ui-date--open');
            trigger.setAttribute('aria-expanded', 'false');
            document.removeEventListener('mousedown', onDoc, true);
            document.removeEventListener('keydown', onKey, true);
            window.removeEventListener('resize', position);
            window.removeEventListener('scroll', position, true);
            if (openPicker === api) openPicker = null;
        }

        function position() {
            var rect = trigger.getBoundingClientRect();
            var width = pop.offsetWidth || 280;
            var height = pop.offsetHeight || 320;
            var margin = 8;
            var rtl = (document.documentElement.dir || document.body.dir) === 'rtl';
            var top = rect.bottom + 6;
            var left = rtl ? rect.right - width : rect.left;
            if (top + height > window.innerHeight - margin) top = rect.top - height - 6;
            if (top < margin) top = margin;
            if (left + width > window.innerWidth - margin) left = window.innerWidth - width - margin;
            if (left < margin) left = margin;
            pop.style.top = top + 'px';
            pop.style.left = left + 'px';
        }

        function commit(iso) {
            if (iso && !inRange(iso)) return;
            var changed = read() !== iso;
            if (changed) {
                write(iso);
                paint();
                input.dispatchEvent(new Event('input', { bubbles: true }));
                input.dispatchEvent(new Event('change', { bubbles: true }));
            }
            close();
            trigger.focus();
        }

        function shiftMonth(delta) {
            var date = new Date(viewYear, viewMonth + delta, 1);
            viewYear = date.getFullYear();
            viewMonth = date.getMonth();
            render();
            position();
        }

        function render() {
            var selected = read();
            var today = todayIso();
            var first = new Date(viewYear, viewMonth, 1);
            var startOffset = (first.getDay() - firstDay + 7) % 7;
            var cursor = new Date(viewYear, viewMonth, 1 - startOffset);
            var labels = weekdayLabels(firstDay);

            var head = '' +
                '<div class="ui-date__head">' +
                    '<button type="button" class="ui-date__nav" data-nav="-12" aria-label="Previous year">' + ICONS.chevsL + '</button>' +
                    '<button type="button" class="ui-date__nav" data-nav="-1" aria-label="Previous month">' + ICONS.chevL + '</button>' +
                    '<div class="ui-date__title">' + esc(monthTitle(viewYear, viewMonth)) + '</div>' +
                    '<button type="button" class="ui-date__nav" data-nav="1" aria-label="Next month">' + ICONS.chevR + '</button>' +
                    '<button type="button" class="ui-date__nav" data-nav="12" aria-label="Next year">' + ICONS.chevsR + '</button>' +
                '</div>';

            var week = '<div class="ui-date__week">';
            labels.forEach(function (label) {
                week += '<div class="ui-date__dow">' + esc(label) + '</div>';
            });
            week += '</div>';

            var grid = '<div class="ui-date__grid" role="grid">';
            for (var i = 0; i < 42; i += 1) {
                var date = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + i);
                var iso = toIso(date);
                var classes = 'ui-date__day';
                if (date.getMonth() !== viewMonth) classes += ' ui-date__day--out';
                if (iso === today) classes += ' ui-date__day--today';
                if (iso === selected) classes += ' ui-date__day--selected';
                var disabled = !inRange(iso);
                grid += '<button type="button" class="' + classes + '" data-iso="' + iso + '" role="gridcell"' +
                    (iso === selected ? ' aria-selected="true"' : '') +
                    (disabled ? ' disabled' : '') +
                    '>' + date.getDate() + '</button>';
            }
            grid += '</div>';

            var foot = '<div class="ui-date__foot">';
            if (allowClear) {
                foot += '<button type="button" data-action="clear"' + (selected ? '' : ' disabled') + '>' + esc(clearLabel) + '</button>';
            } else {
                foot += '<span></span>';
            }
            foot += '<button type="button" data-action="today"' + (inRange(today) ? '' : ' disabled') + '>' + esc(todayLabel) + '</button>';
            foot += '</div>';

            pop.innerHTML = head + week + grid + foot;
        }

        function open() {
            if (input.disabled) return;
            if (openPicker && openPicker !== api) openPicker.close();
            var current = parseIso(read()) || new Date();
            viewYear = current.getFullYear();
            viewMonth = current.getMonth();
            render();
            pop.hidden = false;
            wrap.classList.add('ui-date--open');
            trigger.setAttribute('aria-expanded', 'true');
            position();
            openPicker = api;
            document.addEventListener('mousedown', onDoc, true);
            document.addEventListener('keydown', onKey, true);
            window.addEventListener('resize', position);
            window.addEventListener('scroll', position, true);
            var selectedBtn = pop.querySelector('.ui-date__day--selected') || pop.querySelector('[data-iso="' + todayIso() + '"]');
            if (selectedBtn && !selectedBtn.disabled) selectedBtn.focus();
        }

        function onDoc(event) {
            if (wrap.contains(event.target) || pop.contains(event.target)) return;
            close();
        }

        function moveFocus(deltaDays) {
            var active = document.activeElement;
            var iso = active && active.dataset ? active.dataset.iso : '';
            var base = parseIso(iso) || parseIso(read()) || new Date();
            var next = new Date(base.getFullYear(), base.getMonth(), base.getDate() + deltaDays);
            viewYear = next.getFullYear();
            viewMonth = next.getMonth();
            render();
            position();
            var btn = pop.querySelector('[data-iso="' + toIso(next) + '"]');
            if (btn) btn.focus();
        }

        function onKey(event) {
            if (event.key === 'Escape') {
                event.preventDefault();
                close();
                trigger.focus();
                return;
            }
            if (!pop.contains(document.activeElement)) return;
            if (event.key === 'ArrowLeft') { event.preventDefault(); moveFocus(-1); }
            else if (event.key === 'ArrowRight') { event.preventDefault(); moveFocus(1); }
            else if (event.key === 'ArrowUp') { event.preventDefault(); moveFocus(-7); }
            else if (event.key === 'ArrowDown') { event.preventDefault(); moveFocus(7); }
            else if (event.key === 'PageUp') { event.preventDefault(); shiftMonth(event.shiftKey ? -12 : -1); }
            else if (event.key === 'PageDown') { event.preventDefault(); shiftMonth(event.shiftKey ? 12 : 1); }
        }

        trigger.addEventListener('click', function () {
            if (pop.hidden) open();
            else close();
        });

        pop.addEventListener('click', function (event) {
            var nav = event.target.closest('[data-nav]');
            if (nav) {
                shiftMonth(Number(nav.dataset.nav));
                return;
            }
            var day = event.target.closest('[data-iso]');
            if (day && !day.disabled) {
                commit(day.dataset.iso);
                return;
            }
            var action = event.target.closest('[data-action]');
            if (!action || action.disabled) return;
            if (action.dataset.action === 'today') commit(todayIso());
            if (action.dataset.action === 'clear') commit('');
        });

        Object.defineProperty(input, 'value', {
            configurable: true,
            enumerable: true,
            get: function () { return valueProp.get.call(this); },
            set: function (next) {
                valueProp.set.call(this, next == null ? '' : String(next));
                paint();
                if (!pop.hidden) {
                    var parsed = parseIso(valueProp.get.call(this));
                    if (parsed) {
                        viewYear = parsed.getFullYear();
                        viewMonth = parsed.getMonth();
                    }
                    render();
                    position();
                }
            },
        });

        new MutationObserver(function () {
            paint();
        }).observe(input, { attributes: true, attributeFilter: ['disabled', 'min', 'max', 'title', 'placeholder'] });

        function discardDetached() {
            close();
            if (pop.parentNode) pop.parentNode.removeChild(pop);
            if (wrap.parentNode) wrap.parentNode.removeChild(wrap);
            delete input._uiDatePicker;
            delete input._uiDateCleanup;
        }

        var api = { open: open, close: close, refresh: paint, _pop: pop };
        input._uiDatePicker = api;
        input._uiDateCleanup = discardDetached;
        trackInput(input);
        trigger.setAttribute('aria-haspopup', 'dialog');
        trigger.setAttribute('aria-expanded', 'false');
        paint();
        return api;
    }

    function enhanceAll(root, options) {
        var scope = root && root.querySelectorAll ? root : document;
        if (scope.matches && scope.matches('[data-ui-date]')) enhance(scope, options);
        scope.querySelectorAll('[data-ui-date]').forEach(function (el) {
            enhance(el, options);
        });
    }

    global.UiDatePicker = {
        enhance: enhance,
        enhanceAll: enhanceAll,
        destroy: destroy,
        format: formatIso,
    };
}(window));
