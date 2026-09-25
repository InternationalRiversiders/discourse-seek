import { foodRequests } from "./food-request-queue";

// Share only images still displayed by mounted elements. Last release cancels
// the request and revokes the blob; private images do not survive navigation.
export class ImageRequests {
  constructor(queue = foodRequests) {
    this.queue = queue;
    this.entries = new Map();
  }

  acquire(url) {
    let entry = this.entries.get(url);
    if (!entry) {
      entry = { refs: 0 };
      entry.task = this.queue.enqueue(async (signal) => {
        const response = await fetch(url, { credentials: "same-origin", signal });
        if (!response.ok) {
          const error = new Error("Image request failed");
          error.status = response.status;
          error.retryAfter = response.headers.get("Retry-After");
          throw error;
        }
        const blob = await response.blob();
        if (signal.aborted || !entry.refs) {
          throw new DOMException("Cancelled", "AbortError");
        }
        entry.objectUrl = URL.createObjectURL(blob);
        return entry.objectUrl;
      });
      entry.task.promise.catch(() => {
        if (this.entries.get(url) === entry) {
          this.entries.delete(url);
        }
      });
      this.entries.set(url, entry);
    }
    entry.refs++;
    let released = false;
    return {
      promise: entry.task.promise,
      release: () => {
        if (released) {
          return;
        }
        released = true;
        if (--entry.refs === 0) {
          if (this.entries.get(url) === entry) {
            this.entries.delete(url);
          }
          entry.task.cancel();
          if (entry.objectUrl) {
            URL.revokeObjectURL(entry.objectUrl);
          }
        }
      },
    };
  }
}

export const foodImages = new ImageRequests();
