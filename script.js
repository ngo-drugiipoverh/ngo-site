(() => {
  const track = document.getElementById("teamTrack");
  if (!track) return;

  const carousel = track.closest(".team-carousel");
  const btnLeft = carousel.querySelector(".carousel-arrow.left");
  const btnRight = carousel.querySelector(".carousel-arrow.right");

  // === Настройки ===
  const GAP = 14;                 // должен совпадать с CSS gap
  const SPEED_PX_PER_SEC = 28;    // скорость "плывущих" карточек
  const PAUSE_ON_HOVER = true;

  // Оригинальные карточки
  const originals = Array.from(track.children);
  if (originals.length < 2) return;

  // Шаг = ширина карточки + gap
  const getStep = () => {
    const card = track.querySelector(".person");
    const w = card ? Math.round(card.getBoundingClientRect().width) : 220;
    return w + GAP;
  };

  // Клонирование для бесконечности
  const cloneAll = (nodes, tag) =>
    nodes.map((n) => {
      const c = n.cloneNode(true);
      c.setAttribute("data-clone", tag);
      c.setAttribute("aria-hidden", "true");
      c.querySelectorAll("a,button,input,textarea,select").forEach(el => el.setAttribute("tabindex", "-1"));
      return c;
    });

  const leftClones = cloneAll(originals, "left");
  const rightClones = cloneAll(originals, "right");

  // [left clones reversed] + [originals] + [right clones]
  leftClones.reverse().forEach(c => track.insertBefore(c, track.firstChild));
  rightClones.forEach(c => track.appendChild(c));

  let step = getStep();

  // Индекс в "карточках" (целое), и смещение в пикселях (вещественное)
  // стартуем на первом оригинале
  const baseIndex = originals.length;
  let index = baseIndex;
  let offsetPx = index * step; // текущее смещение в px (сколько "прокручено" вправо)
  let raf = null;
  let lastTs = null;

  // Пауза
  let paused = false;

  // Плавный толчок стрелками (анимируем transform transition)
  let nudging = false;

  const applyTransform = (withTransition) => {
    if (withTransition) track.classList.add("is-nudging");
    else track.classList.remove("is-nudging");

    track.style.transform = `translate3d(${-offsetPx}px, 0, 0)`;
  };

  // Начальная отрисовка
  applyTransform(false);

  const jumpIfNeeded = () => {
    // У нас есть: leftClones (N) + originals (N) + rightClones (N)
    // Держим offsetPx в пределах "центрального" диапазона, чтобы было бесконечно.
    const N = originals.length;
    const minPx = N * step;           // начало оригиналов
    const maxPx = (N * 2) * step;     // конец оригиналов

    // если ушли слишком вправо (в правые клоны) — вернуть в оригиналы
    if (offsetPx >= maxPx) {
      offsetPx -= N * step;
      applyTransform(false);
    }

    // если ушли слишком влево (в левые клоны) — вернуть в оригиналы
    if (offsetPx < minPx) {
      offsetPx += N * step;
      applyTransform(false);
    }
  };

  const tick = (ts) => {
    if (!lastTs) lastTs = ts;
    const dt = (ts - lastTs) / 1000;
    lastTs = ts;

    if (!paused && !nudging) {
      offsetPx += SPEED_PX_PER_SEC * dt;
      applyTransform(false);
      jumpIfNeeded();
    }

    raf = requestAnimationFrame(tick);
  };

  raf = requestAnimationFrame(tick);

  // Ресайз: пересчитать шаг и скорректировать offsetPx к новому шагу (чтобы не прыгало)
  const onResize = () => {
    const oldStep = step;
    step = getStep();
    if (step === oldStep) return;

    // Пересчёт offsetPx относительно текущей "позиции" в карточках:
    // берем текущий прогресс в шагах и умножаем на новый step
    const progressSteps = offsetPx / oldStep;
    offsetPx = progressSteps * step;
    applyTransform(false);
    jumpIfNeeded();
  };
  window.addEventListener("resize", onResize);

  // Толчок на 1 карточку вправо/влево
  const nudge = (dir) => {
    if (nudging) return;
    nudging = true;

    // целевой offset
    const target = offsetPx + dir * step;

    // включаем transition только на этот "толчок"
    applyTransform(true);
    offsetPx = target;
    applyTransform(true);

    const onEnd = () => {
      track.removeEventListener("transitionend", onEnd);
      nudging = false;
      // выключаем transition и нормализуем бесконечность
      applyTransform(false);
      jumpIfNeeded();
    };
    track.addEventListener("transitionend", onEnd);
  };

  btnRight?.addEventListener("click", () => nudge(+1));
  btnLeft?.addEventListener("click", () => nudge(-1));

  // Клавиши
  carousel.addEventListener("keydown", (e) => {
    if (e.key === "ArrowRight") { e.preventDefault(); nudge(+1); }
    if (e.key === "ArrowLeft") { e.preventDefault(); nudge(-1); }
  });
  carousel.setAttribute("tabindex", "0");

  // Пауза при ховере/фокусе
  const setPause = (v) => { paused = v; };

  if (PAUSE_ON_HOVER) {
    carousel.addEventListener("mouseenter", () => setPause(true));
    carousel.addEventListener("mouseleave", () => setPause(false));
    carousel.addEventListener("focusin", () => setPause(true));
    carousel.addEventListener("focusout", () => setPause(false));
  }

  // На мобилке: если палец держит — пауза (приятно)
  carousel.addEventListener("touchstart", () => setPause(true), { passive: true });
  carousel.addEventListener("touchend", () => setPause(false), { passive: true });
})();