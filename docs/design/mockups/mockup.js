// Shared script for all design mockups. Each page loads it at the end of
// <body>, before its own page-only <script>.

const root = document.documentElement;
const params = new URLSearchParams(location.search);

// Mockup only: switch colours with the buttons or ?direction=a in the URL.
const directionButtons = document.querySelectorAll(".switcher button[data-dir]");
function setDirection(dir) {
  root.dataset.direction = dir;
  directionButtons.forEach(function (b) { b.setAttribute("aria-pressed", b.dataset.dir === dir); });
}
directionButtons.forEach(function (b) { b.addEventListener("click", function () { setDirection(b.dataset.dir); }); });
setDirection(params.get("direction") || "a");

// Mockup only: URL switches for comparing versions side by side.
// ?nav=serif shows the nav links in Sentient instead of Switzer.
root.dataset.nav = params.get("nav") || "sans";
// ?buttons=medium shows button text in Medium instead of Regular.
root.dataset.buttons = params.get("buttons") || "regular";
// ?sides=sea shows the busier sea photo; ?sides=none removes the side water.
root.dataset.sides = params.get("sides") || "wave";
// ?header=aligned lines the header up with the content.
root.dataset.header = params.get("header") || "full";
// ?mat=gap | grey — tile frame (default: thin outline, no mat).
root.dataset.mat = params.get("mat") || "line";
// ?tiles=whole shows artwork tiles uncropped on their mats.
root.dataset.tiles = params.get("tiles") || "crop";
// ?width=1200 | 1400 | 1600 sets where the page stops growing
// (default: no limit, always 80%).
root.dataset.width = params.get("width") || "none";
// ?hat=ripples uses the other water photo; ?hat=none removes the photo.
root.dataset.hat = params.get("hat") || "wave";
// ?arrows=light shows the slightly stronger carousel arrows.
root.dataset.arrows = params.get("arrows") || "lighter";
// ?fonts=plain shows the old system font for comparison.
root.dataset.fonts = params.get("fonts") || "trial";

// Dividers: straight lines (default) or ?divider=spiral for the spiral crest.
const dividerButtons = document.querySelectorAll(".switcher button[data-divider]");
function setDivider(name) {
  root.dataset.divider = name;
  dividerButtons.forEach(function (b) { b.setAttribute("aria-pressed", b.dataset.divider === name); });
}
dividerButtons.forEach(function (b) { b.addEventListener("click", function () { setDivider(b.dataset.divider); }); });
setDivider(params.get("divider") || "straight");

// Carousels: arrows step through the photos (wrapping around); dots (if
// the carousel has a .carousel-dots element) show position. Works for
// every element with class "carousel" on the page.
// Optional thumbnails: give a carousel data-thumbs="<id>" pointing at a
// row of <img> thumbnails; clicking one shows that photo, and the current
// one is marked with class "current".
function setUpCarousel(carousel) {
  const slides = carousel.querySelectorAll("img");
  const dots = carousel.querySelector(".carousel-dots");
  const thumbsRow = carousel.dataset.thumbs ? document.getElementById(carousel.dataset.thumbs) : null;
  const thumbs = thumbsRow ? thumbsRow.querySelectorAll("img") : [];
  let currentSlide = 0;
  if (dots) {
    slides.forEach(function () { dots.appendChild(document.createElement("span")); });
  }
  function showSlide(index) {
    currentSlide = (index + slides.length) % slides.length;
    slides.forEach(function (img, i) { img.hidden = i !== currentSlide; });
    if (dots) {
      dots.querySelectorAll("span").forEach(function (dot, i) { dot.classList.toggle("current", i === currentSlide); });
    }
    thumbs.forEach(function (thumb, i) { thumb.classList.toggle("current", i === currentSlide); });
  }
  carousel.querySelector(".prev").addEventListener("click", function () { showSlide(currentSlide - 1); });
  carousel.querySelector(".next").addEventListener("click", function () { showSlide(currentSlide + 1); });
  thumbs.forEach(function (thumb, i) { thumb.addEventListener("click", function () { showSlide(i); }); });
  showSlide(0);
}
document.querySelectorAll(".carousel").forEach(setUpCarousel);

// Category bar "«" / "»" (phones): tapping scrolls the bar left or right.
// "»" hides at the right end, "«" hides at the left end (the start).
const catsBar = document.querySelector("nav.cats .wrap");
const catsMore = document.getElementById("cats-more");
const catsLess = document.getElementById("cats-less");
function updateCatsButtons() {
  const atStart = catsBar.scrollLeft <= 2;
  const atEnd = catsBar.scrollLeft + catsBar.clientWidth >= catsBar.scrollWidth - 2;
  catsLess.hidden = atStart;
  catsMore.hidden = atEnd;
}
catsMore.addEventListener("click", function () {
  catsBar.scrollBy({ left: catsBar.clientWidth * 0.7, behavior: "smooth" });
});
catsLess.addEventListener("click", function () {
  catsBar.scrollBy({ left: -catsBar.clientWidth * 0.7, behavior: "smooth" });
});
catsBar.addEventListener("scroll", updateCatsButtons);
window.addEventListener("resize", updateCatsButtons);
updateCatsButtons();
