import { apiInitializer } from "discourse/lib/api";
export default apiInitializer((api) => {
  // The shared Campus Life section owns application links when installed.
  if (api.container.lookup("service:site-settings").alumni_map_enabled) { return; }
  if (!api.container.lookup("service:site-settings").food_enabled) { return; }
  api.addSidebarSection((BaseSection, BaseLink) => {
    return class extends BaseSection {
      get name() { return "food"; }
      get title() { return "觅电"; }
      get text() { return "觅电"; }
      get displaySection() { return true; }
      get links() { return [new (class extends BaseLink {
        get name() { return "food"; }
        get route() { return "food"; }
        get text() { return "觅电"; }
        get title() { return this.text; }
        get prefixType() { return "icon"; }
        get prefixValue() { return "utensils"; }
      })()]; }
    };
  });
});
