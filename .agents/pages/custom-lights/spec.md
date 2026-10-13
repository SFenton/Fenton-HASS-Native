# Custom Lights

> **What:** platform-neutral spec for the Custom Lights page (web route `custom-lights`). **Read when:** changing Custom Lights on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/pages/CustomLightsPage.tsx`, `src/components/hass/LightBrightnessCard.tsx`, `LightMoreInfoSheet.tsx`; copy `src/i18n/locales/en/pages/customLights.json`. Entry: Home Quick Links "Custom Lights".

Section "Front Yard":

1. "Manually Control Front Yard Lights" toggle (`input_boolean.manually_control_front_yard_lights`, subtitle On/Off).
2. While on: "Lighting Mode" button showing `input_select.front_yard_custom_lights` and its swatch; opens a picker of the select's options (fallback Default, Custom, Seahawks, Valentine's Day) → `input_select.select_option`. Swatches: Seahawks rgb(0,255,0)→rgb(0,0,255); Valentine's Day rgb(255,0,0)→rgb(255,0,234); Custom the eight lights' live `rgb_color`, de-duplicated, darkest to brightest; Default none.
3. While on and in Custom mode: a brightness tile per light (Left Door Light `light.front_door_exterior_left_light`, Right Door Light `light.front_door_exterior_light_v2`, Bollard 1-6 `light.front_door_bollard_1…6`). Tap opens the light's sheet; drag sets brightness. Then "Reset All Lights" → `light.turn_on` `light.front_yard_lights` {color_temp_kelvin: 2000, brightness: 255, transition: 1}.

Light sheet (title = light): brightness tile (tap toggles). For lights with an hs/rgb/rgbw/rgbww/xy color mode: color → `light.turn_on` {rgb_color}; Reset (the same 2000 K payload on this light); Apply to All Lights (`light.front_yard_lights` {rgb_color: this light's}); Other Lights, each copying that light's color onto this one (disabled while it has none).
