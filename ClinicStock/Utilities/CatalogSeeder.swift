//
//  CatalogSeeder.swift
//  ClinicStock
//
//  Created by Mohamed Kaid
//

import Foundation
import FirebaseFirestore
import Combine

class CatalogSeeder: ObservableObject {

    @Published var status: String = "Ready"
    @Published var isSeeding: Bool = false
    @Published var isComplete: Bool = false
    @Published var progress: Int = 0
    @Published var total: Int = 0

    private let db = Firestore.firestore()

    // ══════════════════════════════════════════════════════
    // MARK: - Run this ONCE as platform admin
    // ══════════════════════════════════════════════════════

    func seedCatalog() async {
        await MainActor.run {
            isSeeding = true
            status = "Building catalog..."
        }

        let codes = allDMECodes()

        await MainActor.run {
            self.total = codes.count
            self.progress = 0
        }

        await updateStatus("Seeding \(codes.count) DME codes...")

        var successCount = 0
        var failCount = 0

        for entry in codes {
            let code = entry["hcpcsCode"] as? String ?? "unknown"
            do {
                // Use the HCPCS code as the document ID for fast direct lookup
                try await db.collection("hcpcsCatalog")
                    .document(code)
                    .setData(entry, merge: true)
                successCount += 1
            } catch {
                print("Failed to seed \(code): \(error)")
                failCount += 1
            }

            await MainActor.run {
                self.progress += 1
            }
        }

        await MainActor.run {
            self.isSeeding = false
            self.isComplete = true
            self.status = "Done — \(successCount) codes seeded, \(failCount) failed"
        }

        print("Catalog seeding complete: \(successCount) success, \(failCount) failed")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - All DME codes
    // Covers E, L, A, K code ranges relevant to clinics.
    // Clinical names are from 2026 CMS HCPCS Level II.
    // commonNames are plain English terms clinics actually use.
    // ══════════════════════════════════════════════════════

    private func allDMECodes() -> [[String: Any]] {
        return eCodes() + lCodes() + aCodes() + kCodes()
    }

    // ── E Codes — Durable Medical Equipment ──────────────

    private func eCodes() -> [[String: Any]] {
        return [

            // Mobility Aids
            makeEntry(
                code: "E0100",
                clinical: "Cane, includes canes of all materials, adjustable or fixed, with tips",
                common: ["cane", "walking cane", "quad cane", "single point cane"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0105",
                clinical: "Cane, quad or three-prong, includes canes of all materials, adjustable or fixed, with tips",
                common: ["quad cane", "4 point cane", "three prong cane", "wide base cane"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0110",
                clinical: "Crutches, forearm, includes crutches of various materials, adjustable or fixed, pair, complete with tips and handgrips",
                common: ["crutches", "forearm crutches", "lofstrand crutches", "pair of crutches"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0111",
                clinical: "Crutch, forearm, includes crutches of various materials, adjustable or fixed, each, with tip and handgrip",
                common: ["single crutch", "one crutch", "forearm crutch each"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0114",
                clinical: "Crutches, underarm, wood, adjustable or fixed, pair, complete with pads, tips and handgrips",
                common: ["underarm crutches", "axillary crutches", "standard crutches", "wooden crutches"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0116",
                clinical: "Crutch, underarm, adjustable or fixed, each, with pad, tip, and handgrip, any material",
                common: ["single underarm crutch", "axillary crutch each"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0130",
                clinical: "Walker, rigid (pickup), adjustable or fixed height",
                common: ["walker", "pickup walker", "standard walker", "rigid walker"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0135",
                clinical: "Walker, folding (pickup), adjustable or fixed height",
                common: ["folding walker", "collapsible walker", "foldable walker"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0141",
                clinical: "Walker, rigid, wheeled, adjustable or fixed height",
                common: ["wheeled walker", "rolling walker", "front wheel walker", "2 wheel walker"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0143",
                clinical: "Walker, folding, wheeled, adjustable or fixed height",
                common: ["folding wheeled walker", "collapsible rolling walker"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0144",
                clinical: "Walker, enclosed, four-sided framed, wheeled, rigid or folding, any type, each",
                common: ["enclosed walker", "4 wheel walker", "quad wheel walker", "rollator"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0148",
                clinical: "Walker, heavy duty, without wheels, adjustable or fixed height",
                common: ["heavy duty walker", "bariatric walker"],
                category: "Mobility Aids"
            ),
            makeEntry(
                code: "E0149",
                clinical: "Walker, heavy duty, wheeled, rigid or folding, any type",
                common: ["heavy duty wheeled walker", "bariatric rolling walker"],
                category: "Mobility Aids"
            ),

            // Electrical Stimulation
            makeEntry(
                code: "E0720",
                clinical: "Transcutaneous electrical nerve stimulation (TENS) device, two lead, localized stimulation",
                common: ["tens unit", "tens machine", "electrical stimulation unit", "nerve stimulator", "TENS 2 lead"],
                category: "Electrical Stimulation"
            ),
            makeEntry(
                code: "E0730",
                clinical: "Transcutaneous electrical nerve stimulation (TENS) device, four lead, larger area or multiple stimulation",
                common: ["tens unit 4 lead", "tens machine 4 channel", "TENS 4 lead", "four channel tens"],
                category: "Electrical Stimulation"
            ),
            makeEntry(
                code: "E0731",
                clinical: "Form fitting conductive garment for delivery of TENS or NMS (with conductive fibers separated from the patient's skin by layers of fabric)",
                common: ["tens garment", "conductive garment", "NMS garment"],
                category: "Electrical Stimulation"
            ),

            // Traction
            makeEntry(
                code: "E0840",
                clinical: "Traction frame, attached to headboard, cervical traction",
                common: ["cervical traction frame", "neck traction frame", "over door traction"],
                category: "Traction"
            ),
            makeEntry(
                code: "E0849",
                clinical: "Traction equipment, cervical, free-standing stand/frame, pneumatic, applying traction force to the cervical spine",
                common: ["pneumatic cervical traction", "cervical traction device", "neck traction device"],
                category: "Traction"
            ),
            makeEntry(
                code: "E0855",
                clinical: "Cervical traction equipment not requiring additional stand or frame",
                common: ["cervical traction", "neck traction", "over door cervical traction"],
                category: "Traction"
            ),

            // Heat / Cold Therapy
            makeEntry(
                code: "E0210",
                clinical: "Electric heat pad, standard",
                common: ["heating pad", "electric heat pad", "hot pad"],
                category: "Heat Therapy"
            ),
            makeEntry(
                code: "E0215",
                clinical: "Electric heat pad, moist",
                common: ["moist heating pad", "moist heat pad"],
                category: "Heat Therapy"
            ),
            makeEntry(
                code: "E0217",
                clinical: "Water circulating heat pad with pump",
                common: ["water circulating heat pad", "hydrocollator pad", "aqua therapy pad"],
                category: "Heat Therapy"
            ),
            makeEntry(
                code: "E0221",
                clinical: "Infrared heating pad system",
                common: ["infrared heating pad", "IR heat pad"],
                category: "Heat Therapy"
            ),

            // Respiratory
            makeEntry(
                code: "E0470",
                clinical: "Respiratory assist device, bi-level pressure capability, without back-up rate feature, used with noninvasive interface",
                common: ["bipap", "bilevel pap", "bi-level respiratory device", "bipap machine"],
                category: "Respiratory"
            ),
            makeEntry(
                code: "E0471",
                clinical: "Respiratory assist device, bi-level pressure capability, with back-up rate feature, used with noninvasive interface",
                common: ["bipap with backup rate", "bilevel with backup"],
                category: "Respiratory"
            ),
            makeEntry(
                code: "E0601",
                clinical: "Continuous positive airway pressure (CPAP) device",
                common: ["cpap", "cpap machine", "cpap device", "sleep apnea machine"],
                category: "Respiratory"
            ),

            // Wheelchairs — basic
            makeEntry(
                code: "E1130",
                clinical: "Standard wheelchair, fixed full length arms, fixed or swing away detachable footrests",
                common: ["standard wheelchair", "manual wheelchair", "basic wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "E1161",
                clinical: "Manual adult size wheelchair, includes tilt in space",
                common: ["tilt in space wheelchair", "tilt wheelchair"],
                category: "Wheelchairs"
            ),
        ]
    }

    // ── L Codes — Orthotic Procedures ────────────────────

    private func lCodes() -> [[String: Any]] {
        return [

            // Cervical Orthoses
            makeEntry(
                code: "E0120",
                clinical: "Cervical orthosis, collar, soft, prefabricated, includes fitting and adjustment",
                common: ["soft cervical collar", "foam neck collar", "soft neck brace", "cervical collar soft"],
                category: "Cervical"
            ),
            makeEntry(
                code: "L0172",
                clinical: "Cervical orthosis, collar, semi-rigid thermoplastic foam and rigid material, prefabricated, includes fitting and adjustment",
                common: ["semi rigid cervical collar", "coretech cervical collar", "hard cervical collar", "rigid neck brace", "philadelphia collar"],
                category: "Cervical"
            ),
            makeEntry(
                code: "L0174",
                clinical: "Cervical orthosis, collar, semi-rigid thermoplastic foam and rigid material, occipital/mandibular support, prefabricated, includes fitting and adjustment",
                common: ["cervical collar with chin support", "semi rigid collar chin support"],
                category: "Cervical"
            ),

            // Lumbar / Thoracic Orthoses
            makeEntry(
                code: "L0620",
                clinical: "Abdominal orthosis, panel design, prefabricated, includes fitting and adjustment",
                common: ["abdominal binder", "ab binder", "belly binder", "abdominal support", "post surgical binder"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0621",
                clinical: "Sacroiliac orthosis, flexible, prefabricated, includes fitting and adjustment",
                common: ["SI belt", "sacroiliac belt", "SI joint belt", "pelvic belt", "coretech SI belt"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0622",
                clinical: "Sacroiliac orthosis, flexible, custom fabricated",
                common: ["custom SI belt", "custom sacroiliac orthosis"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0623",
                clinical: "Sacroiliac orthosis, provides pelvic-sacral support, with rigid or semi-rigid panels over the sacrum and pelvis, prefabricated, includes fitting and adjustment",
                common: ["rigid SI brace", "sacroiliac support with panels"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0625",
                clinical: "Lumbar orthosis, flexible, provides lumbar support, prefabricated, includes fitting and adjustment",
                common: ["LSO brace", "lumbar brace", "back brace", "lumbar support", "lower back brace", "LSO"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0626",
                clinical: "Lumbar orthosis, sagittal control, with rigid anterior and posterior panels, prefabricated, includes fitting and adjustment",
                common: ["rigid lumbar brace", "lumbar brace with panels", "LSO rigid"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0627",
                clinical: "Lumbar orthosis, sagittal control, with rigid anterior and posterior panels, custom fabricated",
                common: ["custom lumbar brace", "custom LSO"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0628",
                clinical: "Lumbar-sacral orthosis, flexible, provides lumbo-sacral support, prefabricated, includes fitting and adjustment",
                common: ["TLSO flexible", "lumbosacral brace", "LSO flexible"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0629",
                clinical: "Lumbar-sacral orthosis, flexible, custom fabricated",
                common: ["custom lumbosacral brace"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0631",
                clinical: "Lumbar-sacral orthosis, sagittal control, with rigid anterior and posterior panels, prefabricated, includes fitting and adjustment",
                common: ["rigid lumbosacral brace", "TLSO rigid panels"],
                category: "Lumbar"
            ),
            makeEntry(
                code: "L0637",
                clinical: "Lumbar-sacral orthosis, sagittal-coronal control, with rigid anterior and posterior frame/panels, prefabricated, includes fitting and adjustment",
                common: ["TLSO coronal control", "thoracolumbar brace"],
                category: "Lumbar"
            ),

            // Knee Orthoses
            makeEntry(
                code: "L1820",
                clinical: "Knee orthosis, elastic with joints, prefabricated, includes fitting and adjustment",
                common: ["knee brace", "hinged knee brace", "knee support with hinges", "elastic knee brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1830",
                clinical: "Knee orthosis, immobilizer, canvas longitudinal, prefabricated, includes fitting and adjustment",
                common: ["knee immobilizer", "knee splint", "canvas knee immobilizer", "straight knee brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1832",
                clinical: "Knee orthosis, adjustable knee joints (unicentric or polycentric), positional orthosis, rigid support, prefabricated, includes fitting and adjustment",
                common: ["ROM knee brace", "range of motion knee brace", "adjustable knee brace", "post op knee brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1833",
                clinical: "Knee orthosis, adjustable knee joints (unicentric or polycentric), positional orthosis, rigid support, custom fabricated",
                common: ["custom ROM knee brace", "custom range of motion brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1843",
                clinical: "Knee orthosis, single upright, thigh and calf, with adjustable flexion and extension joint, medial-lateral and rotation control, with or without varus/valgus adjustment, prefabricated, includes fitting and adjustment",
                common: ["OA knee brace", "unloader knee brace", "offloader knee brace", "osteoarthritis knee brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1844",
                clinical: "Knee orthosis, single upright, thigh and calf, with adjustable flexion and extension joint, medial-lateral and rotation control, with or without varus/valgus adjustment, custom fabricated",
                common: ["custom OA knee brace", "custom unloader knee brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1845",
                clinical: "Knee orthosis, double upright, thigh and calf, with adjustable flexion and extension joint, medial-lateral and rotation control, with or without varus/valgus adjustment, prefabricated, includes fitting and adjustment",
                common: ["double upright knee brace", "bilateral knee brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1847",
                clinical: "Knee orthosis, dynamic, soft interface, pediatric size, prefabricated",
                common: ["pediatric knee brace", "kids knee brace", "dynamic knee orthosis pediatric"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1851",
                clinical: "Knee orthosis, with or without joint(s), prefabricated, includes fitting and adjustment",
                common: ["basic knee brace", "simple knee orthosis", "knee sleeve with joint"],
                category: "Orthopedic"
            ),

            // Ankle / Foot Orthoses
            makeEntry(
                code: "L1900",
                clinical: "Ankle-foot orthosis, spring wire, dorsiflexion assist calf band, custom fabricated",
                common: ["AFO spring wire", "ankle foot orthosis", "drop foot brace custom"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1902",
                clinical: "Ankle-foot orthosis, ankle gauntlet, prefabricated, includes fitting and adjustment",
                common: ["ankle gauntlet", "ankle orthosis", "AFO ankle gauntlet"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1906",
                clinical: "Ankle-foot orthosis, multiligamentous ankle support, prefabricated, includes fitting and adjustment",
                common: ["ankle brace", "lace up ankle brace", "ankle support", "ankle stabilizer"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1907",
                clinical: "Ankle orthosis, supramalleolar with straps, with or without interface/pads, custom fabricated",
                common: ["SMO", "supramalleolar orthosis", "custom ankle brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1930",
                clinical: "Ankle-foot orthosis, plastic or other material, prefabricated, includes fitting and adjustment",
                common: ["plastic AFO", "prefab AFO", "drop foot AFO", "foot drop brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1940",
                clinical: "Ankle-foot orthosis, plastic or other material, custom fabricated",
                common: ["custom AFO", "custom plastic AFO", "custom drop foot brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L1971",
                clinical: "Ankle-foot orthosis, plastic, prefabricated, includes fitting and adjustment",
                common: ["walking boot", "cam boot", "cam walker", "fracture boot", "moon boot"],
                category: "Orthopedic"
            ),

            // Wrist / Hand Orthoses
            makeEntry(
                code: "L3900",
                clinical: "Wrist-hand-finger orthosis, dynamic flexion, with outrigger, custom fabricated",
                common: ["dynamic wrist brace", "wrist hand finger orthosis custom"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3906",
                clinical: "Wrist-hand orthosis, without joints, prefabricated, includes fitting and adjustment",
                common: ["wrist splint", "wrist immobilizer", "carpal tunnel brace", "cock up splint"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3908",
                clinical: "Wrist-hand orthosis, wrist extension control cock-up, nonmolded, prefabricated, includes fitting and adjustment",
                common: ["wrist brace", "wrist support", "cock up wrist brace", "wrist cock up splint"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3913",
                clinical: "Hand finger orthosis, without joints, may include soft interface material, prefabricated, includes fitting and adjustment",
                common: ["finger splint", "hand orthosis", "buddy splint", "mallet finger splint"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3916",
                clinical: "Hand finger orthosis, without joints, may include soft interface material, custom fabricated",
                common: ["custom finger splint", "custom hand orthosis"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3923",
                clinical: "Hand finger orthosis, without joints, includes thermal plastic, elastic or other material, prefabricated, includes fitting and adjustment",
                common: ["thumb brace", "thumb spica", "de quervain brace", "thumb stabilizer"],
                category: "Orthopedic"
            ),

            // Elbow Orthoses
            makeEntry(
                code: "L3702",
                clinical: "Elbow orthosis, without joints, may include soft interface material, prefabricated, includes fitting and adjustment",
                common: ["elbow brace", "tennis elbow brace", "lateral epicondylitis brace", "elbow strap"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3710",
                clinical: "Elbow orthosis, elastic with stays, prefabricated, includes fitting and adjustment",
                common: ["elbow sleeve with stays", "elbow immobilizer"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3720",
                clinical: "Elbow orthosis, double upright with forearm/arm cuffs, free motion, custom fabricated",
                common: ["elbow hinged brace", "double upright elbow brace", "custom elbow brace"],
                category: "Orthopedic"
            ),

            // Shoulder Orthoses
            makeEntry(
                code: "L3650",
                clinical: "Shoulder orthosis, figure of eight design, abduction restrainer, prefabricated, includes fitting and adjustment",
                common: ["shoulder brace", "figure of eight brace", "shoulder immobilizer", "shoulder sling and swathe"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3660",
                clinical: "Shoulder orthosis, figure of eight design, abduction restrainer, custom fabricated",
                common: ["custom shoulder brace", "custom figure of eight"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3670",
                clinical: "Shoulder orthosis, acromio/clavicular (canvas and webbing type), prefabricated, includes fitting and adjustment",
                common: ["AC brace", "acromioclavicular brace", "clavicle brace"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3671",
                clinical: "Shoulder orthosis, shoulder cap design, without joints, may include soft interface material, prefabricated, includes fitting and adjustment",
                common: ["shoulder cap brace", "shoulder orthosis cap"],
                category: "Orthopedic"
            ),
            makeEntry(
                code: "L3675",
                clinical: "Shoulder orthosis, shoulder cap design, without joints, may include soft interface material, custom fabricated",
                common: ["custom shoulder cap brace"],
                category: "Orthopedic"
            ),
        ]
    }

    // ── A Codes — Medical / Surgical Supplies ─────────────

    private func aCodes() -> [[String: Any]] {
        return [

            // Wound Care
            makeEntry(
                code: "A6010",
                clinical: "Collagen based wound filler, dry form, sterile, per gram of collagen",
                common: ["collagen wound filler", "dry collagen wound dressing"],
                category: "Wound Care"
            ),
            makeEntry(
                code: "A6021",
                clinical: "Collagen dressing, pad size 16 sq. in. or less, sterile, each",
                common: ["collagen dressing small", "wound dressing collagen pad"],
                category: "Wound Care"
            ),
            makeEntry(
                code: "A6216",
                clinical: "Gauze, non-impregnated, non-sterile, pad size 16 sq. in. or less, without adhesive border, each dressing",
                common: ["gauze pad", "non sterile gauze", "gauze dressing"],
                category: "Wound Care"
            ),
            makeEntry(
                code: "A6217",
                clinical: "Gauze, non-impregnated, non-sterile, pad size more than 16 sq. in. but less than or equal to 48 sq. in., without adhesive border, each dressing",
                common: ["large gauze pad", "gauze dressing large"],
                category: "Wound Care"
            ),
            makeEntry(
                code: "A6250",
                clinical: "Skin sealants, protectants, moisturizers, ointments, any type, any size",
                common: ["skin sealant", "wound protectant", "skin protectant", "moisture barrier"],
                category: "Wound Care"
            ),

            // Compression
            makeEntry(
                code: "A6530",
                clinical: "Gradient compression stocking, below knee, 18-30 mmHg, each",
                common: ["compression stocking below knee", "knee high compression stocking 20-30", "compression socks"],
                category: "Compression"
            ),
            makeEntry(
                code: "A6531",
                clinical: "Gradient compression stocking, below knee, 30-40 mmHg, each",
                common: ["compression stocking 30-40", "high compression stocking knee high", "medical compression stocking"],
                category: "Compression"
            ),
            makeEntry(
                code: "A6532",
                clinical: "Gradient compression stocking, full length/chap style, 18-30 mmHg, each",
                common: ["full length compression stocking", "thigh high compression stocking"],
                category: "Compression"
            ),
            makeEntry(
                code: "A6544",
                clinical: "Gradient compression stocking, garter belt",
                common: ["compression stocking garter belt", "stocking garter"],
                category: "Compression"
            ),
            makeEntry(
                code: "A6549",
                clinical: "Gradient compression garment, not otherwise specified",
                common: ["compression garment", "compression sleeve", "lymphedema garment"],
                category: "Compression"
            ),

            // Diabetic Supplies
            makeEntry(
                code: "A5500",
                clinical: "For diabetics only, fitting (including follow-up), custom preparation and supply of off-the-shelf depth-inlay shoe manufactured to accommodate multi-density insert(s), per shoe",
                common: ["diabetic shoe", "depth inlay shoe", "therapeutic diabetic shoe"],
                category: "Diabetic Supplies"
            ),
            makeEntry(
                code: "A5501",
                clinical: "For diabetics only, fitting (including follow-up), custom preparation and supply of shoe molded from cast(s) of patient's foot (custom molded shoe), per shoe",
                common: ["custom molded diabetic shoe", "custom diabetic shoe"],
                category: "Diabetic Supplies"
            ),
            makeEntry(
                code: "A5512",
                clinical: "For diabetics only, multiple density insert, prefabricated, per insole",
                common: ["diabetic insert", "diabetic insole", "multi density insole"],
                category: "Diabetic Supplies"
            ),
            makeEntry(
                code: "A5513",
                clinical: "For diabetics only, multiple density insert, custom molded from model of patient's foot, per insole",
                common: ["custom diabetic insole", "custom molded insert diabetic"],
                category: "Diabetic Supplies"
            ),

            // Slings
            makeEntry(
                code: "A4565",
                clinical: "Slings",
                common: ["arm sling", "shoulder sling", "sling", "figure of eight sling"],
                category: "Orthopedic"
            ),
        ]
    }

    // ── K Codes — DME (Specific to Durable Medical Equipment) ──

    private func kCodes() -> [[String: Any]] {
        return [
            makeEntry(
                code: "K0001",
                clinical: "Standard manual wheelchair",
                common: ["manual wheelchair", "standard wheelchair", "basic wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "K0002",
                clinical: "Standard hemi (low seat) wheelchair",
                common: ["hemi wheelchair", "low seat wheelchair", "hemiplegic wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "K0003",
                clinical: "Lightweight wheelchair",
                common: ["lightweight wheelchair", "light wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "K0004",
                clinical: "High strength, lightweight wheelchair",
                common: ["high strength wheelchair", "ultra lightweight wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "K0005",
                clinical: "Ultralightweight wheelchair",
                common: ["ultra light wheelchair", "ultralight wheelchair", "sport wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "K0006",
                clinical: "Heavy duty wheelchair",
                common: ["heavy duty wheelchair", "bariatric wheelchair", "oversized wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "K0007",
                clinical: "Extra heavy duty wheelchair",
                common: ["extra heavy duty wheelchair", "bariatric heavy wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "K0008",
                clinical: "Custom manual wheelchair/base",
                common: ["custom wheelchair", "custom manual wheelchair"],
                category: "Wheelchairs"
            ),
            makeEntry(
                code: "K0669",
                clinical: "Wheelchair accessory, wheelchair seat or back cushion, does not meet the requirements described in E2601-E2611, E2613, E2614, E2619-E2623 or E2626-E2633",
                common: ["wheelchair cushion", "seat cushion wheelchair", "back cushion wheelchair"],
                category: "Wheelchairs"
            ),
        ]
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Helper
    // ══════════════════════════════════════════════════════

    private func makeEntry(
        code: String,
        clinical: String,
        common: [String],
        category: String
    ) -> [String: Any] {
        return [
            "hcpcsCode": code,
            "clinicalName": clinical,
            "commonNames": common,
            "category": category,
            "gtins": [] as [String],
            "isActive": true,
            "lastUpdated": Timestamp(date: Date()),
            "sourceYear": 2026
        ]
    }

    private func updateStatus(_ message: String) async {
        await MainActor.run {
            status = message
        }
        print(message)
    }
}
