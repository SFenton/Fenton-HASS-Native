# Live Activities: proposed Home Assistant automations (Phase 1, not applied)

> **What:** the automations that let Home Assistant start, update and end the Home Live Activity while the app is closed, and answer its buttons, before the `fenton_push` job engine (Phase 2) exists. **Read when:** the owner applies them, or Phase 2 replaces them. Nothing here has been applied: no agent changes `/config` without the owner's approval and a backup of each file first.

They use only what is verified in [live-activities.md](live-activities.md) §0: core `mobile_app` routes a `notify` call with `data.live_update: true` and `data.tag` to a **start** (the phone's push-to-start token), an **update** (the activity's token) or, for `clear_notification`, an **end**; `ha-fenton-push` (Phase 1 branch `live-activities-phase1`) turns the `data.fenton_activity` block into the activity's content. Install that integration version first; without it the block is ignored and the post is dropped.

Entities are the ones read on 2026-10-17. Replace `notify.mobile_app_stephen_s_iphone_fenton` with your own device service (Developer Tools, Actions, search `mobile_app`); add one `repeat` entry per phone that should show the activity.

## 1. One script builds the whole list

The activity lists every running job, so every trigger calls this script and it sends the full list (an `update` for a job changing replaces the content).

```yaml
script:
  fenton_home_activity_push:
    alias: Fenton Home activity push
    mode: queued
    fields:
      alert:
        description: "true when something finished and needs a person (quiet start, sound update)"
        default: false
    sequence:
      - variables:
          now_ts: "{{ now().timestamp() | int }}"
          op: "{{ states('sensor.dishwasher_operation_state') }}"
          dish_end: "{{ as_timestamp(states('sensor.dishwasher_program_finish_time'), 0) | int }}"
          dish_running: "{{ op in ['run', 'pause'] }}"
          dish_done: "{{ op == 'finished' }}"
          progress: "{{ (states('sensor.dishwasher_program_progress') | float(0)) / 100 }}"
          program: "{{ states('select.dishwasher_active_program') | replace('dishcare_dishwasher_program_', '') | replace('_', ' ') | title }}"
          jobs: >-
            {% set ns = namespace(out=[]) %}
            {% if dish_running %}
              {% set controls = [{'id': 'stop', 'title': 'Stop', 'role': 'destructive'}] if is_state('binary_sensor.dishwasher_remote_control', 'on') else [] %}
              {% set ns.out = ns.out + [{'id': 'dishwasher', 'kind': 'dishwasher', 'title': 'Dishwasher',
                   'status': program ~ ' · ' ~ ((progress * 100) | round(0) | int) ~ '%',
                   'phase': 'paused' if op == 'pause' else 'running',
                   'start_ts': states.sensor.dishwasher_operation_state.last_changed.timestamp() | int,
                   'end_ts': dish_end, 'progress': progress, 'symbol': 'dishwasher', 'tint': 'cleaning',
                   'controls': controls}] %}
            {% elif dish_done %}
              {% set ns.out = ns.out + [{'id': 'dishwasher', 'kind': 'dishwasher', 'title': 'Dishwasher', 'status': 'Clean',
                   'phase': 'done', 'symbol': 'dishwasher', 'tint': 'cleaning'}] %}
            {% endif %}
            {% for room in ['guest', 'master'] %}
              {% set pending = 'input_boolean.' ~ room ~ '_bathroom_fan_timer_pending' %}
              {% set end = state_attr('input_datetime.' ~ room ~ '_bathroom_fan_timer_ends_at', 'timestamp') | int(0) %}
              {% if is_state(pending, 'on') and end > now_ts %}
                {% set ns.out = ns.out + [{'id': 'fan.' ~ room, 'kind': 'bathroom_fan', 'title': room | title ~ ' Bath Fan',
                     'status': 'Off in', 'phase': 'running',
                     'start_ts': states[pending].last_changed.timestamp() | int,
                     'end_ts': end, 'symbol': 'fan', 'tint': 'air',
                     'controls': [{'id': 'cancel_timer', 'title': 'Cancel Timer'}]}] %}
              {% endif %}
            {% endfor %}
            {{ ns.out | tojson }}
      - choose:
          # Nothing is running and nothing is finishing: end the activity.
          - conditions: "{{ jobs | from_json | length == 0 }}"
            sequence:
              - action: notify.mobile_app_stephen_s_iphone_fenton
                data:
                  message: clear_notification
                  data:
                    tag: fenton-home
        default:
          - action: notify.mobile_app_stephen_s_iphone_fenton
            data:
              title: Home
              message: "{{ (jobs | from_json)[0].title }} · {{ (jobs | from_json)[0].status }}"
              data:
                tag: fenton-home
                live_update: true
                live_alert: "{{ alert }}"
                fenton_activity:
                  focus: "{{ (jobs | from_json)[0].id }}"
                  url: "/sfenton-react-dash/home?path=kitchen"
                  jobs: "{{ jobs | from_json }}"
```

Notes:

- `message` is also the alert body of the quiet start ("Dishwasher · Eco 50° · 62%").
- The relay cuts to 6 jobs, 40-character status and 2 controls, and keeps only `id`, `title` and `role` of a control: the service a control maps to is below and never reaches the phone.
- The stale date defaults to the earliest end plus 10 minutes. The 5-minute refresh below keeps it fresh.
- `focus` here is always the most urgent job. The pager changes the phone's focus locally; the next push resets it (the Phase 2 engine remembers it per device, spec §6 rule 8).

## 2. Triggers

```yaml
automation:
  - alias: Fenton Home activity, dishwasher changes
    triggers:
      - trigger: state
        entity_id: sensor.dishwasher_operation_state
      - trigger: time_pattern   # progress moves a point every ~2 minutes; five is enough for the bar and the stale date
        minutes: "/5"
    conditions:
      - condition: template
        value_template: "{{ states('sensor.dishwasher_operation_state') in ['run','pause','finished','delayedstart','actionrequired','error','aborting'] or trigger.platform == 'state' }}"
    actions:
      - action: script.fenton_home_activity_push
        data:
          alert: "{{ trigger.platform == 'state' and trigger.to_state.state in ['finished', 'actionrequired', 'error'] }}"

  - alias: Fenton Home activity, bathroom fan timers
    triggers:
      - trigger: state
        entity_id:
          - input_boolean.guest_bathroom_fan_timer_pending
          - input_boolean.master_bathroom_fan_timer_pending
    actions:
      - action: script.fenton_home_activity_push

  - alias: Fenton Home activity, end the dishwasher's Done row
    triggers:
      - trigger: state
        entity_id: sensor.dishwasher_operation_state
        from: finished
        to: ready          # Home Connect clears "finished" after ~10 minutes; the linger is Home Assistant's
    actions:
      - action: script.fenton_home_activity_push
```

## 3. Buttons

The app fires `fenton_live_activity_action {tag, job, control}` over the registration webhook (it carries the signed-in user). The automation checks the control is one the job offers and then calls the service. Verified services:

| Job | Control | Service |
|---|---|---|
| dishwasher | `stop` | `button.press` `button.dishwasher_stop_program` (needs `binary_sensor.dishwasher_remote_control` on) |
| dishwasher | `resume` | `button.press` `button.dishwasher_resume_program` (only while `pause`) |
| fan.guest, fan.master | `cancel_timer` | `script.<room>_bathroom_fan_command` with `command: timer_cancel` (the fan keeps running: open question 2) |

```yaml
automation:
  - alias: Fenton Home activity, buttons
    triggers:
      - trigger: event
        event_type: fenton_live_activity_action
    conditions:
      - condition: template   # only people who are signed in to Fenton Home; add an audience check per job in Phase 2
        value_template: "{{ trigger.event.context.user_id is not none }}"
    actions:
      - choose:
          - conditions: "{{ trigger.event.data.job == 'dishwasher' and trigger.event.data.control == 'stop' }}"
            sequence:
              - action: button.press
                target: {entity_id: button.dishwasher_stop_program}
          - conditions: "{{ trigger.event.data.job == 'dishwasher' and trigger.event.data.control == 'resume' and is_state('sensor.dishwasher_operation_state', 'pause') }}"
            sequence:
              - action: button.press
                target: {entity_id: button.dishwasher_resume_program}
          - conditions: "{{ trigger.event.data.job in ['fan.guest', 'fan.master'] and trigger.event.data.control == 'cancel_timer' }}"
            sequence:
              - action: "script.{{ trigger.event.data.job.split('.')[1] }}_bathroom_fan_command"
                data: {command: timer_cancel}
      # The confirmed state replaces the phone's optimistic "Stopping…" (a failed press puts the button back).
      - delay: "00:00:03"
      - action: script.fenton_home_activity_push
```

`fenton_live_activity_focus` and `fenton_live_activity_dismissed` need no automation in Phase 1; they are in the event log for the engine.

## 4. Check it once applied (owner, on the phone)

See the device checks in [live-activities.md](live-activities.md) §11. In short: Developer Tools, Actions, call the script while a fan timer runs, and read Apple's Push Notifications Console for delivery.
