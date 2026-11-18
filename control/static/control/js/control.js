function showToast(message) {
  const toast = document.getElementById("control-toast");
  if (!toast) return;
  toast.textContent = message;
  toast.hidden = false;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => {
    toast.hidden = true;
  }, 1600);
}

function copyText(text) {
  if (!text) return;
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).then(
      () => showToast("Copied"),
      () => copyWithFallback(text)
    );
    return;
  }
  copyWithFallback(text);
}

function copyWithFallback(text) {
  const area = document.createElement("textarea");
  area.value = text;
  area.setAttribute("readonly", "");
  area.style.position = "fixed";
  area.style.left = "-9999px";
  document.body.appendChild(area);
  area.select();
  try {
    document.execCommand("copy");
    showToast("Copied");
  } catch (error) {
    window.prompt("Copy this value:", text);
  }
  area.remove();
}

function setNav(open) {
  const sidebar = document.querySelector("[data-sidebar]");
  const backdrop = document.querySelector("[data-nav-backdrop]");
  if (!sidebar) return;
  sidebar.classList.toggle("is-open", open);
  if (backdrop) backdrop.hidden = !open;
}

document.addEventListener("click", (event) => {
  if (event.target.closest("[data-nav-toggle]")) {
    const sidebar = document.querySelector("[data-sidebar]");
    setNav(!sidebar || !sidebar.classList.contains("is-open"));
    return;
  }
  if (event.target.closest("[data-nav-backdrop]")) {
    setNav(false);
    return;
  }

  const copyButton = event.target.closest("[data-copy]");
  if (copyButton) {
    event.preventDefault();
    copyText(copyButton.getAttribute("data-copy"));
    return;
  }

  const reveal = event.target.closest("[data-toggle-secret]");
  if (reveal) {
    const target = document.getElementById(reveal.getAttribute("data-toggle-secret"));
    if (!target) return;
    const visible = target.getAttribute("data-visible") === "true";
    target.setAttribute("data-visible", visible ? "false" : "true");
    reveal.textContent = visible ? "Show" : "Hide";
    return;
  }

  const sectionTab = event.target.closest("[data-section-tab]");
  if (sectionTab && !event.metaKey && !event.ctrlKey && !event.shiftKey) {
    const selected = sectionTab.getAttribute("data-section-tab") || "all";
    const panels = document.querySelectorAll("[data-detail-section]");
    if (panels.length) {
      event.preventDefault();
      panels.forEach((panel) => {
        const name = panel.getAttribute("data-detail-section");
        panel.hidden = selected !== "all" && name !== selected;
      });
      document.querySelectorAll("[data-section-tab]").forEach((tab) => {
        const active = tab.getAttribute("data-section-tab") === selected;
        tab.classList.toggle("control-section-tab-active", active);
        tab.setAttribute("aria-selected", active ? "true" : "false");
      });
      if (window.history && window.history.replaceState) {
        const url = new URL(window.location.href);
        if (selected === "all") {
          url.searchParams.delete("section");
        } else {
          url.searchParams.set("section", selected);
        }
        window.history.replaceState({}, "", url.toString());
      }
      return;
    }
  }

  const row = event.target.closest("[data-href]");
  if (row && !event.target.closest("a, button, input, label, form")) {
    window.location.href = row.getAttribute("data-href");
  }
});

document.addEventListener("submit", (event) => {
  const button = event.submitter;
  const message = button && button.getAttribute("data-confirm");
  if (message && !window.confirm(message)) {
    event.preventDefault();
  }
});

document.addEventListener("DOMContentLoaded", () => {
  const slug = document.getElementById("id_slug");
  const preview = document.getElementById("host-preview");
  if (slug && preview) {
    const domain = preview.getAttribute("data-domain") || "localhost";
    const render = () => {
      const value = (slug.value || "").trim().toLowerCase() || "your-slug";
      preview.textContent = `${value}.${domain}`;
    };
    slug.addEventListener("input", render);
    render();
  }

  const planSelect = document.querySelector("[data-plan-select]");
  const seatInput = document.querySelector("[data-seat-input]");
  if (planSelect && seatInput) {
    planSelect.addEventListener("change", () => {
      const option = planSelect.selectedOptions[0];
      if (option && option.dataset.seats) {
        seatInput.value = option.dataset.seats;
      }
    });
  }

  const filter = document.getElementById("operator-filter");
  if (filter) {
    filter.addEventListener("input", () => {
      const needle = filter.value.trim().toLowerCase();
      document.querySelectorAll("[data-operator]").forEach((row) => {
        const haystack = (row.getAttribute("data-operator") || "").toLowerCase();
        row.hidden = Boolean(needle) && !haystack.includes(needle);
      });
    });
  }
});
