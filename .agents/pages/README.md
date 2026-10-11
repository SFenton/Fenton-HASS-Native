# Pages

> **What:** one folder per web route with a platform-neutral spec and per-platform notes. **Read when:** porting or changing a page.

Full screen map: [dashboard inventory](https://claude.ai/code/artifact/bba4d82d-2e8f-4aee-b216-8256aa97f47c).

| Page | Web route | Spec | Native status |
|---|---|---|---|
| Home | `/at-a-glance/overview` | [home/spec.md](home/spec.md) | Scaffolded ([ios.md](home/ios.md)) |
| Security | `/at-a-glance/security` | TODO | Placeholder |
| Climate | `/at-a-glance/thermostat` | TODO | Placeholder |
| Chores | `/at-a-glance/chores` | TODO | Placeholder |
| Settings | `/at-a-glance/settings` | TODO | Home Assistant settings modal only ([ios.md](settings/ios.md)) |
| Inventory (All Food, Pantry, Fridge, Freezer, Spice Rack, Cabinet) | `/food-and-recipes/<space>` | [inventory/spec.md](inventory/spec.md) | Pages, item editor and Add Item ([ios.md](inventory/ios.md)); reached from the Food & Recipes hub once it lands |
