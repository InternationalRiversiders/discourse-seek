import { modifier } from "ember-modifier";
import { foodImages } from "../lib/food-images";

export default modifier((element, [url]) => {
  if (!url) {
    return;
  }
  if (!/^\/food\/media\/\d+$/.test(url)) {
    element.src = url;
    return () => element.removeAttribute("src");
  }
  let ticket;
  let loaded = false;
  let disposed = false;
  const release = () => {
    ticket?.release();
    ticket = undefined;
  };
  const load = () => {
    if (ticket || loaded || disposed) {
      return;
    }
    const current = (ticket = foodImages.acquire(url));
    current.promise.then((src) => {
      if (!disposed && ticket === current) {
        element.src = src;
        loaded = true;
        delete element.dataset.loadFailed;
      }
    }).catch((error) => {
      if (!disposed && ticket === current) {
        release();
        if (error.name !== "AbortError") {
          element.dataset.loadFailed = "true";
        }
      }
    });
  };
  const observer = window.IntersectionObserver && new IntersectionObserver((entries) => {
    if (entries.some((entry) => entry.isIntersecting)) {
      load();
    } else if (!loaded) {
      release();
    }
  }, { rootMargin: "150px" });
  if (observer) {
    observer.observe(element);
  } else {
    load();
  }
  element.addEventListener("click", load);
  return () => {
    disposed = true;
    observer?.disconnect();
    element.removeEventListener("click", load);
    element.removeAttribute("src");
    release();
  };
});
