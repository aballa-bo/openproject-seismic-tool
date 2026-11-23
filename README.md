# OpenProject Seismic tool

OpenProject plugin (tested design target: OpenProject 16.6 and 17) with two features.

## 1. Damage detection from images
* Pick one or more **documents** of a project (e.g. `/documents/18`); every image attached to them is analysed.
* Detects the 7 MSD-Det classes (cracks, fabric loss, surface dissolution, efflorescence, discolouration, plant, moss)
  and segments cracks pixel by pixel (cascade of a YOLOv5-x detector and a YOLO-seg model, ported from `masonry_det`).
* Per image: overlay JPEG, crack mask, detections with box, confidence and, for cracks, area / length / mean width (px).
* Job page with live progress, cancel / retry / delete.
* **Results in Documents:** when a job is done, the images are copied to the project's Documents: for a source document
  `X`, the labelled images go to `X_labeled` (`photo_labeled.jpg`) and the crack masks to `X_masked` (`photo_masked.png`),
  same category as `X`. This happens the first time someone who can manage documents opens the finished job; the button
  *Copy images to Documents* repeats it (only new images are added). Working copies stay under
  `<attachments>/seismic_tool/jobs/<job id>/`.

### Queue and worker (does not slow the server)
* The queue is a PostgreSQL table (`seismic_jobs`, `seismic_image_results`); the unit of work is **one image**, so
  progress is fine-grained and a cancel takes effect at the next image.
* The worker is a separate Python process (`worker/`), run by systemd as `openproject-seismic-worker`:
  `Nice=19`, `CPUSchedulingPolicy=idle`, `IOSchedulingClass=idle`, `CPUWeight=1`, `CPUQuota=200%`, memory ceiling,
  `OOMScoreAdjust=900` (killed first under memory pressure), 2 torch threads, pause between images, and it does not start
  an image while the load average is high. It never runs inside the Rails/Puma processes.
* Jobs claimed with `FOR UPDATE SKIP LOCKED`; images interrupted by a crash are re-queued at start-up.

## 2. From suggestion to verified damage to form
The image analysis never writes damage by itself: it **suggests**.

1. Every detection becomes a *suggestion* (`Seismic tool → Suggestions`), shown as a crop of the image with the box, class,
   confidence and, for cracks, length/width. Cracks are *structural* suggestions; the other classes (fabric loss, dissolution,
   efflorescence, discolouration, plants, moss) are *non structural*.
2. The **verifier** (anyone allowed to add work packages in the project) opens *Verify…* and, if the damage is real, fills in what
   the form needs: collapse mechanism 1–28 (structural) or the element (non structural), damage level 0–5, kind
   (seismic / pre-existing / aggravation), emergency measures (A20) and extent. *Confirm* creates a work package of type
   **AeDES – Danno strutturale** or **AeDES – Danno non strutturale** with those custom fields and a link to the image;
   *Reject* dismisses the suggestion.
3. The **survey form is compiled from those work packages**: A16 (worst level per mechanism, with its kind), A17 (damage index
   `id = d / 5n`), A20 (measures, limited/extended) and A21 (non structural damage). *Update damage from AeDES work packages*
   refreshes these sections at any time, so work packages created or edited by hand count too.

The migration creates the two work package types and their custom fields (`AeDES …`), and copies the workflows of the standard
type; if something cannot be created it says so and the same names can be created by hand in the administration.

## 3. Damage survey forms
`Seismic tool → Damage survey forms → Create` builds a form pre-filled from the project and lets you edit it
(sections saved as JSON, printable via the browser's *Print / Save as PDF*):

* **Modello A-DC – Chiese** (PCM-DPC / MiBAC 2006, default): sections A1–A27, with the abacus of the 28 collapse mechanisms (A16).
* **GL-AeDES 01/2014** (prefabricated / large-span buildings), kept as a selectable type (no work package compilation).

Pre-filled from: project name, the **"Building data (AeDES)" project custom fields** created by the migration (region,
province, municipality, ISTAT code, address, cadastral data, dating, user, main dimensions...), the 3D viewer's location,
the logged-in user (compiler), the damage work packages and a summary of the image analysis (notes). The schemas are
declarative (`app/services/seismic_tool/adc_schema.rb`, `aedes_schema.rb`); new forms are registered in `forms.rb`.

> The forms do not replace the inspector's judgement or any structural verification.

## Install
```
sudo bash install.sh
```
Then enable the module *Seismic tool* in the project settings, grant the permissions to the roles, and check
`journalctl -u openproject-seismic-worker -f`. Weights: see `MODELS.md`.
Images must live on the local disk (default attachment storage); S3/fog storage is not supported.

## Permissions
`view_seismic_tool`, `run_seismic_analysis`, `edit_aedes_forms` (create/edit survey forms).

## Sections

The plugin page is split in three sections (tab bar at the top):

1. **Masonry defect detection** – queue of image analyses, suggestions for the verifier.
2. **AeDES form** – survey forms (A-DC churches, GL-AeDES) compiled from project data and confirmed AeDES work packages.
3. **Crack modelling** – pick one image, get a 3D relief (coloured point cloud + mesh, viewable in the browser and downloadable as `.ply` / `.obj`).
   Depth comes from Depth Anything V2 Small (downloaded by `install.sh` into `models/depth_anything_v2_small`); the geometry
   (pinhole back-projection, meshing that skips depth jumps) is implemented in `worker/seismic_worker/reconstruct.py`
   following the approach of <https://github.com/greenaandblue/Single-Image-to-3D-Reconstruction> (no code copied: the repository has no licence).
   Cracks are segmented with the same crack model as the detection, painted red and optionally engraved.
   The result is a relative-scale 2.5D relief, not a closed model.
