export function retryDelay(error, now = Date.now()) {
  const value = error?.getResponseHeader?.("Retry-After") ?? error?.retryAfter;
  if (value && /^\d+(\.\d+)?$/.test(String(value).trim())) {
    return Math.max(1000, Number(value) * 1000);
  }
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.max(1000, date - now) : 60000;
}

// One budget for navigation and media. Cancelling a view removes its queued work;
// a 429 pauses the whole queue rather than starting a retry per component.
export class RequestQueue {
  constructor({ interval = 400, concurrency = 2 } = {}) {
    this.interval = interval;
    this.concurrency = concurrency;
    this.pending = [];
    this.active = 0;
    this.nextStart = 0;
    this.blockedUntil = 0;
  }

  enqueue(run, { priority = 0, delay = 0 } = {}) {
    const controller = new AbortController();
    const job = { run, priority, controller, readyAt: Date.now() + delay };
    const promise = new Promise((resolve, reject) => Object.assign(job, { resolve, reject }));
    this.pending.push(job);
    this.pump();
    return {
      promise,
      cancel: () => {
        controller.abort();
        this.pending = this.pending.filter((item) => item !== job);
        job.reject(new DOMException("Cancelled", "AbortError"));
        this.pump();
      },
    };
  }

  pump() {
    clearTimeout(this.timer);
    this.timer = undefined;
    if (!this.pending.length || this.active >= this.concurrency) {
      return;
    }
    const now = Date.now();
    const earliest = Math.max(this.nextStart, this.blockedUntil, Math.min(...this.pending.map((job) => job.readyAt)));
    if (earliest > now) {
      this.timer = setTimeout(() => this.pump(), earliest - now);
      return;
    }
    const ready = this.pending.filter((job) => job.readyAt <= now).sort((a, b) => b.priority - a.priority);
    const job = ready[0];
    this.pending.splice(this.pending.indexOf(job), 1);
    this.active++;
    this.nextStart = now + this.interval;
    Promise.resolve().then(() => job.run(job.controller.signal)).then(job.resolve, (error) => {
      if (error?.status === 429) {
        this.blockedUntil = Math.max(this.blockedUntil, Date.now() + retryDelay(error));
      }
      job.reject(error);
    }).finally(() => {
      this.active--;
      this.pump();
    });
    this.pump();
  }
}

export const foodRequests = new RequestQueue();
