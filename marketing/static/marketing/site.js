// Mobile navigation. Everything else on the site works without JavaScript.
(function () {
  var toggle = document.querySelector("[data-nav-toggle]");
  var nav = document.querySelector("[data-nav]");
  if (!toggle || !nav) return;

  function setOpen(open) {
    if (open) {
      nav.setAttribute("data-open", "");
    } else {
      nav.removeAttribute("data-open");
    }
    toggle.setAttribute("aria-expanded", open ? "true" : "false");
  }

  toggle.addEventListener("click", function () {
    setOpen(!nav.hasAttribute("data-open"));
  });

  nav.addEventListener("click", function (event) {
    if (event.target.closest("a")) setOpen(false);
  });

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") setOpen(false);
  });
})();
