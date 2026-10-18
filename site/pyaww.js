/* Pyaww landing — tiny vanilla helpers. No dependencies, no network. */
(function () {
  "use strict";

  // — Language toggle (EN ⇄ မြန်မာ) —
  var buttons = document.querySelectorAll(".langswitch button");
  function setLang(lang) {
    document.body.classList.toggle("lang-en", lang === "en");
    document.body.classList.toggle("lang-my", lang === "my");
    document.documentElement.lang = lang === "my" ? "my" : "en";
    buttons.forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.lang === lang));
    });
    try { localStorage.setItem("pyaww-lang", lang); } catch (e) {}
  }
  buttons.forEach(function (b) {
    b.addEventListener("click", function () { setLang(b.dataset.lang); });
  });
  var saved = null;
  try { saved = localStorage.getItem("pyaww-lang"); } catch (e) {}
  var prefersMy = (navigator.language || "").toLowerCase().indexOf("my") === 0;
  setLang(saved === "my" || saved === "en" ? saved : (prefersMy ? "my" : "en"));

  // — Hero wave draw-in —
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var path = document.querySelector(".wave-path");
  if (path && !reduce && path.getTotalLength) {
    var len = path.getTotalLength();
    path.style.strokeDasharray = len;
    path.style.strokeDashoffset = len;
    requestAnimationFrame(function () {
      path.style.animation = "draw 1.7s .25s cubic-bezier(.5,.05,.2,1) forwards";
    });
  }
})();
