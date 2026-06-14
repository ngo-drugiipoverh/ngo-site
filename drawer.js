// drawer.js
(() => {
  const drawer = document.getElementById("siteDrawer");
  const overlay = document.querySelector(".drawer-overlay");
  const toggleBtn = document.querySelector(".drawer-toggle");
  const closeBtns = document.querySelectorAll("[data-drawer-close]");

  if (!drawer || !overlay || !toggleBtn) return;

  const open = () => {
    drawer.classList.add("is-open");
    overlay.classList.add("is-open");
    drawer.setAttribute("aria-hidden", "false");
    toggleBtn.setAttribute("aria-expanded", "true");
    document.body.style.overflow = "hidden";
  };

  const close = () => {
    drawer.classList.remove("is-open");
    overlay.classList.remove("is-open");
    drawer.setAttribute("aria-hidden", "true");
    toggleBtn.setAttribute("aria-expanded", "false");
    document.body.style.overflow = "";
  };

  toggleBtn.addEventListener("click", () => {
    const isOpen = drawer.classList.contains("is-open");
    isOpen ? close() : open();
  });

  closeBtns.forEach(btn => btn.addEventListener("click", close));

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") close();
  });

  // закрывать при клике по ссылке
  drawer.addEventListener("click", (e) => {
    const a = e.target.closest("a");
    if (a) close();
  });
})();