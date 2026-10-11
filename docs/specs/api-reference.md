# REST API Reference (ProPresenter v1)

ProPack interacts directly with ProPresenter's local HTTP REST API introduced in ProPresenter 7.9+.

---

## Base URL & Transport

- **Host**: `127.0.0.1` (localhost)
- **Port**: Assigned dynamically by ProPresenter (e.g., `http://127.0.0.1:58123`)
- **Transport**: Plain HTTP (`NSAppTransportSecurity` configured with `NSAllowsLocalNetworking = YES`)
- **Headers**: `Accept: application/json`

---

## Endpoints Used by ProPack

### 1. `GET /version`
Probes the service to check whether the listening port is indeed ProPresenter.

#### Response
```json
{
  "name": "ProPresenter",
  "platform": "mac",
  "os_version": "15.0",
  "host_description": "ProPresenter 7.16",
  "api_version": "v1"
}
```

---

### 2. `GET /v1/playlists`
Retrieves the complete playlist hierarchy, including folders ("groups") and playlist leaves.

#### Response
```json
[
  {
    "id": {
      "uuid": "8F3A2...",
      "name": "Sunday Services",
      "index": 0
    },
    "field_type": "group",
    "children": [
      {
        "id": {
          "uuid": "4C1E9...",
          "name": "Sunday Morning",
          "index": 0
        },
        "field_type": "playlist",
        "children": null
      }
    ]
  }
]
```

---

### 3. `GET /v1/playlist/{id}`
Returns all items contained within the specified playlist.

#### Response
```json
{
  "id": {
    "uuid": "4C1E9...",
    "name": "Sunday Morning"
  },
  "items": [
    {
      "id": {
        "uuid": "ITEM-1",
        "name": "Announcements",
        "index": 0
      },
      "type": "header",
      "is_hidden": false
    },
    {
      "id": {
        "uuid": "ITEM-2",
        "name": "Living Hope",
        "index": 1
      },
      "type": "presentation",
      "is_hidden": false,
      "presentation_info": {
        "presentation_uuid": "PRES-1234",
        "arrangement_name": "Standard Arrangement",
        "arrangement_uuid": "ARR-5678"
      }
    }
  ]
}
```

---

### 4. `GET /v1/presentation/{uuid}`
Returns detailed metadata for an individual presentation document.

#### Response
```json
{
  "presentation": {
    "id": {
      "uuid": "PRES-1234",
      "name": "Living Hope"
    },
    "has_timeline": false,
    "destination": "presentation",
    "presentation_path": "/Users/user/Documents/ProPresenter/Libraries/Default/Living Hope.pro",
    "groups": [
      {
        "name": "Verse 1",
        "color": {
          "red": 0.2,
          "green": 0.6,
          "blue": 0.9,
          "alpha": 1.0
        },
        "slides": [
          {
            "enabled": true,
            "label": "V1",
            "text": "How great the chasm that lay between us...",
            "notes": ""
          }
        ]
      }
    ]
  }
}
```

*Note: In some ProPresenter builds, responses may be wrapped in an envelope object `{ "presentation": { ... } }` or returned as raw objects. ProPack handles both formats seamlessly.*
