# trippy — AI artwork prompt set

This set follows the supplied trippy UI reference: warm ivory surfaces, coral/peach/yellow accents, dark forest-green typography, rounded cards, and editorial travel photography with warm natural light.

## Asset roles

- **Brand mark and wordmark:** the balloon/location-pin mark and lowercase trippy lettering are recreated as clean vectors from the supplied reference so the spelling and proportions stay exact. Use the existing SVG and asset-catalog exports; do not ask an image model to redraw the lettering.
- **Trip-cover artwork:** AI-generated destination mood images used as cover art for trip cards. The first generated six-image sheet is saved at ios/Trippy/Brand/generated-trip-cover-sheet.png; the six crops used by the app are in ios/Trippy/Assets.xcassets/Trip*.imageset/.
- **Future banners and empty-state illustrations:** generate only when those screens are designed. Keep them in the same visual family.
- **Venue imagery and maps:** do not fabricate a real restaurant, museum, hotel, street map, or event photograph. Use verified image URLs and real map data from the imported research or a map provider. Generated artwork can set a mood, but must not look like documentary evidence for a specific venue.

## Shared art direction

Append this block to every artwork prompt:

> Match the trippy travel app art direction: refined editorial travel photography, warm natural late-afternoon light, soft coral and peach highlights, amber sunlight, subtle forest-green shadows, lively but believable color, calm composition, generous visual breathing room, crisp detail, no heavy filters, no text, no logos, no UI, no watermark. The image should feel optimistic, personal, and premium without looking luxurious or staged. Compose for rounded mobile cards and keep the main subject inside the center 70% so portrait crops remain usable.

## 1. Trip-cover image set

Already generated for the prototype as a six-panel sheet. For additional covers, generate each destination as its own image using this template:

> Create one standalone travel-cover photograph for a mobile trip-planning app. Destination: [DESTINATION]. Show one recognizable but naturally photographed sense of place, with a clear foreground, a memorable focal point, and a little atmosphere around it. Vertical 4:5 composition with the important subject inside the middle 70%; no people in close-up. [SHARED ART DIRECTION]

Suggested destinations: Tokyo, Lisbon, Santorini, Bali, Rome, New York, Barcelona, Copenhagen, Marrakech, Iceland.

## 2. City and culture banner

> Create a wide 3:1 editorial travel banner suggesting a walkable city and cultural discovery. Use layered architecture, a quiet street-level detail, and warm light; make it atmospheric rather than a literal tourist checklist. Leave the left third visually quiet for interface text, and keep the most interesting detail to the right. [SHARED ART DIRECTION]

## 3. Coast and island banner

> Create a wide 3:1 editorial travel banner suggesting a slow coastal trip. Use sea, shoreline, and one small architectural or landscape detail; avoid postcard clichés and oversaturated turquoise. Leave the left third visually quiet for interface text. [SHARED ART DIRECTION]

## 4. Nature and outdoors banner

> Create a wide 3:1 editorial travel banner for an outdoors-focused trip. Show a layered landscape and a subtle path that invites exploration, with believable terrain and natural light. Keep the left third visually quiet for interface text. [SHARED ART DIRECTION]

## 5. Food and evening banner

> Create a wide 3:1 editorial travel banner evoking an evening of local food and conversation. Show a carefully composed table detail or warmly lit street-side setting without visible branding, readable menus, or recognizable real venues. Leave the left third quiet for interface text. [SHARED ART DIRECTION]

## 6. Empty-state illustration

> Create a small, simple, original editorial illustration for a travel app empty state about a trip that has not been planned yet. Use a few rounded shapes, a warm ivory background, dark forest-green linework, and restrained coral, peach, and amber accents. Make the image friendly and clever, not childish. Center the illustration with generous blank space; no text, no logo, no interface. [SHARED ART DIRECTION]

## Output and handoff

Request each image as a separate asset when it will be used in the interface. For any contact sheet, require equal panels with straight grid boundaries and no overlap, then crop each panel into its own asset. Keep originals with the project and export optimized JPEG or PNG crops for the app. Do not bake text, labels, card corners, or gradients into the artwork; those belong to the SwiftUI layout.
