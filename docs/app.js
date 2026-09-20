const flowSteps = {
  start: {
    image: "assets/product/onboarding.webp",
    alt: "AIPedometer welcome screen on iPhone",
    label: "A calm first step",
    heading: "Start with a goal you can change later.",
    copy: "The first run explains the product before asking for health access.",
  },
  track: {
    image: "assets/product/dashboard.webp",
    alt: "AIPedometer dashboard showing daily progress on iPhone",
    label: "Daily context",
    heading: "See the goal, the gap, and the next useful action.",
    copy: "The dashboard brings today’s movement and explicit permission states into one view.",
  },
  train: {
    image: "assets/product/active-workout.webp",
    alt: "AIPedometer active outdoor walk screen on iPhone",
    label: "Focused tracking",
    heading: "Keep the live workout readable while you move.",
    copy: "Steps, distance, calories, and elapsed time stay visible with pause and finish controls nearby.",
  },
  progress: {
    image: "assets/product/badges.webp",
    alt: "AIPedometer earned and locked badges screen on iPhone",
    label: "Progress over time",
    heading: "Turn repeat movement into visible milestones.",
    copy: "Earned and upcoming badges make progress legible without turning every walk into a competition.",
  },
};

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const flowButtons = [...document.querySelectorAll("[data-flow]")];
const flowImage = document.querySelector("#flow-image");
const flowLabel = document.querySelector("#flow-label");
const flowHeading = document.querySelector("#flow-heading");
const flowCopy = document.querySelector("#flow-copy");

for (const step of Object.values(flowSteps)) {
  const image = new Image();
  image.src = step.image;
}

function showFlowStep(key) {
  const step = flowSteps[key];
  if (!step || !flowImage || !flowLabel || !flowHeading || !flowCopy) return;

  for (const button of flowButtons) {
    const isActive = button.dataset.flow === key;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
  }

  const update = () => {
    flowImage.src = step.image;
    flowImage.alt = step.alt;
    flowLabel.textContent = step.label;
    flowHeading.textContent = step.heading;
    flowCopy.textContent = step.copy;
    flowImage.classList.remove("is-changing");
  };

  if (reduceMotion) {
    update();
    return;
  }

  flowImage.classList.add("is-changing");
  window.setTimeout(update, 140);
}

for (const button of flowButtons) {
  button.addEventListener("click", () => showFlowStep(button.dataset.flow));
}
