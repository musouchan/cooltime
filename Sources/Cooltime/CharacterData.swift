// 自動生成: scripts/gen_characters.py（characters/menubar/*.svg と characters/motion.json から）。
// 直接は編集しない。絵や動きを変えたら、スクリプトを実行し直す。

enum CharacterData {
    static let ids: [String] = ["bunny", "cat", "bear", "pig", "frog"]
    static let names: [String: String] = ["bunny": "うさぎ", "cat": "ねこ", "bear": "くま", "pig": "ぶた", "frog": "かえる"]

    /// "id-state" → 描く順の部品
    static let shapes: [String: [CharElement]] = [
        "bunny-ok": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 45.547 18.997 C 46.702 29.982 43.363 39.336 38.091 39.89 C 32.818 40.445 27.607 31.989 26.453 21.003 C 25.298 10.018 28.637 0.664 33.909 0.11 C 39.182 -0.445 44.393 8.011 45.547 18.997 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 73.547 21.003 C 72.393 31.989 67.182 40.445 61.909 39.89 C 56.637 39.336 53.298 29.982 54.453 18.997 C 55.607 8.011 60.818 -0.445 66.091 0.11 C 71.363 0.664 74.702 10.018 73.547 21.003 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 37 50.5 L 37 50.5 C 39.899 50.5 42.25 52.851 42.25 55.75 L 42.25 64.25 C 42.25 67.149 39.899 69.5 37 69.5 L 37 69.5 C 34.101 69.5 31.75 67.149 31.75 64.25 L 31.75 55.75 C 31.75 52.851 34.101 50.5 37 50.5 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 63 50.5 L 63 50.5 C 65.899 50.5 68.25 52.851 68.25 55.75 L 68.25 64.25 C 68.25 67.149 65.899 69.5 63 69.5 L 63 69.5 C 60.101 69.5 57.75 67.149 57.75 64.25 L 57.75 55.75 C 57.75 52.851 60.101 50.5 63 50.5 Z"),
        ],
        "bunny-limit": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 45.547 28.997 C 46.24 35.588 42.527 41.38 37.254 41.934 C 31.981 42.488 27.145 37.595 26.453 31.003 C 25.76 24.412 29.473 18.62 34.746 18.066 C 40.019 17.512 44.855 22.405 45.547 28.997 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 73.547 31.003 C 72.855 37.595 68.019 42.488 62.746 41.934 C 57.473 41.38 53.76 35.588 54.453 28.997 C 55.145 22.405 59.981 17.512 65.254 18.066 C 70.527 18.62 74.24 24.412 73.547 31.003 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 30 58 C 34.667 64.667 39.333 64.667 44 58"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 56 58 C 60.667 64.667 65.333 64.667 70 58"),
            CharElement(chain: ["zz"], cutout: false, fill: false, stroke: 5.2, round: true, opacity: 1, path: "M 68 3 L 88 3 L 68 23 L 88 23"),
        ],
        "bunny-fail": [
            CharElement(chain: ["root"], cutout: false, fill: false, stroke: 18.2, round: true, opacity: 1, path: "M 38 36 C 36 24 33 15 22 13"),
            CharElement(chain: ["root"], cutout: false, fill: false, stroke: 18.2, round: true, opacity: 1, path: "M 62 36 C 64 24 67 15 78 13"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 31 54 L 43 66 M 43 54 L 31 66"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 57 54 L 69 66 M 69 54 L 57 66"),
        ],
        "cat-ok": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 21 40 L 25 10 L 46 33 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 79 40 L 75 10 L 54 33 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 37 50.5 L 37 50.5 C 39.899 50.5 42.25 52.851 42.25 55.75 L 42.25 64.25 C 42.25 67.149 39.899 69.5 37 69.5 L 37 69.5 C 34.101 69.5 31.75 67.149 31.75 64.25 L 31.75 55.75 C 31.75 52.851 34.101 50.5 37 50.5 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 63 50.5 L 63 50.5 C 65.899 50.5 68.25 52.851 68.25 55.75 L 68.25 64.25 C 68.25 67.149 65.899 69.5 63 69.5 L 63 69.5 C 60.101 69.5 57.75 67.149 57.75 64.25 L 57.75 55.75 C 57.75 52.851 60.101 50.5 63 50.5 Z"),
        ],
        "cat-limit": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 22 44 L 24 27 L 44 36 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 78 44 L 76 27 L 56 36 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 30 58 C 34.667 64.667 39.333 64.667 44 58"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 56 58 C 60.667 64.667 65.333 64.667 70 58"),
            CharElement(chain: ["zz"], cutout: false, fill: false, stroke: 5.2, round: true, opacity: 1, path: "M 68 3 L 88 3 L 68 23 L 88 23"),
        ],
        "cat-fail": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 27 46 L 6 34 L 27 28 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 73 46 L 94 34 L 73 28 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 31 54 L 43 66 M 43 54 L 31 66"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 57 54 L 69 66 M 69 54 L 57 66"),
        ],
        "bear-ok": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 41 26 C 41 33.18 35.18 39 28 39 C 20.82 39 15 33.18 15 26 C 15 18.82 20.82 13 28 13 C 35.18 13 41 18.82 41 26 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 85 26 C 85 33.18 79.18 39 72 39 C 64.82 39 59 33.18 59 26 C 59 18.82 64.82 13 72 13 C 79.18 13 85 18.82 85 26 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 56.5 69 C 56.5 71.541 53.59 73.6 50 73.6 C 46.41 73.6 43.5 71.541 43.5 69 C 43.5 66.459 46.41 64.4 50 64.4 C 53.59 64.4 56.5 66.459 56.5 69 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 37 45.5 L 37 45.5 C 39.899 45.5 42.25 47.851 42.25 50.75 L 42.25 59.25 C 42.25 62.149 39.899 64.5 37 64.5 L 37 64.5 C 34.101 64.5 31.75 62.149 31.75 59.25 L 31.75 50.75 C 31.75 47.851 34.101 45.5 37 45.5 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 63 45.5 L 63 45.5 C 65.899 45.5 68.25 47.851 68.25 50.75 L 68.25 59.25 C 68.25 62.149 65.899 64.5 63 64.5 L 63 64.5 C 60.101 64.5 57.75 62.149 57.75 59.25 L 57.75 50.75 C 57.75 47.851 60.101 45.5 63 45.5 Z"),
        ],
        "bear-limit": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 37 34 C 37 40.075 32.075 45 26 45 C 19.925 45 15 40.075 15 34 C 15 27.925 19.925 23 26 23 C 32.075 23 37 27.925 37 34 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 85 34 C 85 40.075 80.075 45 74 45 C 67.925 45 63 40.075 63 34 C 63 27.925 67.925 23 74 23 C 80.075 23 85 27.925 85 34 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 56.5 69 C 56.5 71.541 53.59 73.6 50 73.6 C 46.41 73.6 43.5 71.541 43.5 69 C 43.5 66.459 46.41 64.4 50 64.4 C 53.59 64.4 56.5 66.459 56.5 69 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 30 53 C 34.667 59.667 39.333 59.667 44 53"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 56 53 C 60.667 59.667 65.333 59.667 70 53"),
            CharElement(chain: ["zz"], cutout: false, fill: false, stroke: 5.2, round: true, opacity: 1, path: "M 68 3 L 88 3 L 68 23 L 88 23"),
        ],
        "bear-fail": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 24 46 C 24 51.523 19.523 56 14 56 C 8.477 56 4 51.523 4 46 C 4 40.477 8.477 36 14 36 C 19.523 36 24 40.477 24 46 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 96 46 C 96 51.523 91.523 56 86 56 C 80.477 56 76 51.523 76 46 C 76 40.477 80.477 36 86 36 C 91.523 36 96 40.477 96 46 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 56.5 69 C 56.5 71.541 53.59 73.6 50 73.6 C 46.41 73.6 43.5 71.541 43.5 69 C 43.5 66.459 46.41 64.4 50 64.4 C 53.59 64.4 56.5 66.459 56.5 69 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 31 49 L 43 61 M 43 49 L 31 61"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 57 49 L 69 61 M 69 49 L 57 61"),
        ],
        "pig-ok": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 23 40 L 17 14 L 43 31 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 77 40 L 83 14 L 57 31 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: true, stroke: 0, round: false, opacity: 0.95, path: "M 65 72 C 65 77.523 58.284 82 50 82 C 41.716 82 35 77.523 35 72 C 35 66.477 41.716 62 50 62 C 58.284 62 65 66.477 65 72 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 46.8 72 C 46.8 73.546 45.546 74.8 44 74.8 C 42.454 74.8 41.2 73.546 41.2 72 C 41.2 70.454 42.454 69.2 44 69.2 C 45.546 69.2 46.8 70.454 46.8 72 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 58.8 72 C 58.8 73.546 57.546 74.8 56 74.8 C 54.454 74.8 53.2 73.546 53.2 72 C 53.2 70.454 54.454 69.2 56 69.2 C 57.546 69.2 58.8 70.454 58.8 72 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 37 42.5 L 37 42.5 C 39.899 42.5 42.25 44.851 42.25 47.75 L 42.25 56.25 C 42.25 59.149 39.899 61.5 37 61.5 L 37 61.5 C 34.101 61.5 31.75 59.149 31.75 56.25 L 31.75 47.75 C 31.75 44.851 34.101 42.5 37 42.5 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 63 42.5 L 63 42.5 C 65.899 42.5 68.25 44.851 68.25 47.75 L 68.25 56.25 C 68.25 59.149 65.899 61.5 63 61.5 L 63 61.5 C 60.101 61.5 57.75 59.149 57.75 56.25 L 57.75 47.75 C 57.75 44.851 60.101 42.5 63 42.5 Z"),
        ],
        "pig-limit": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 23 44 L 17 28 L 42 35 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 77 44 L 83 28 L 58 35 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: true, stroke: 0, round: false, opacity: 0.95, path: "M 65 72 C 65 77.523 58.284 82 50 82 C 41.716 82 35 77.523 35 72 C 35 66.477 41.716 62 50 62 C 58.284 62 65 66.477 65 72 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 46.8 72 C 46.8 73.546 45.546 74.8 44 74.8 C 42.454 74.8 41.2 73.546 41.2 72 C 41.2 70.454 42.454 69.2 44 69.2 C 45.546 69.2 46.8 70.454 46.8 72 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 58.8 72 C 58.8 73.546 57.546 74.8 56 74.8 C 54.454 74.8 53.2 73.546 53.2 72 C 53.2 70.454 54.454 69.2 56 69.2 C 57.546 69.2 58.8 70.454 58.8 72 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 30 50 C 34.667 56.667 39.333 56.667 44 50"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 56 50 C 60.667 56.667 65.333 56.667 70 50"),
            CharElement(chain: ["zz"], cutout: false, fill: false, stroke: 5.2, round: true, opacity: 1, path: "M 68 3 L 88 3 L 68 23 L 88 23"),
        ],
        "pig-fail": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 23 44 L 4 40 L 22 30 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 6, round: true, opacity: 1, path: "M 77 40 L 83 14 L 57 31 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: true, stroke: 0, round: false, opacity: 0.95, path: "M 65 72 C 65 77.523 58.284 82 50 82 C 41.716 82 35 77.523 35 72 C 35 66.477 41.716 62 50 62 C 58.284 62 65 66.477 65 72 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 46.8 72 C 46.8 73.546 45.546 74.8 44 74.8 C 42.454 74.8 41.2 73.546 41.2 72 C 41.2 70.454 42.454 69.2 44 69.2 C 45.546 69.2 46.8 70.454 46.8 72 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 58.8 72 C 58.8 73.546 57.546 74.8 56 74.8 C 54.454 74.8 53.2 73.546 53.2 72 C 53.2 70.454 54.454 69.2 56 69.2 C 57.546 69.2 58.8 70.454 58.8 72 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 31 46 L 43 58 M 43 46 L 31 58"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 57 46 L 69 58 M 69 46 L 57 58"),
        ],
        "frog-ok": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 47 26 C 47 34.284 40.284 41 32 41 C 23.716 41 17 34.284 17 26 C 17 17.716 23.716 11 32 11 C 40.284 11 47 17.716 47 26 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 83 26 C 83 34.284 76.284 41 68 41 C 59.716 41 53 34.284 53 26 C 53 17.716 59.716 11 68 11 C 76.284 11 83 17.716 83 26 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 41 26 C 41 30.971 36.971 35 32 35 C 27.029 35 23 30.971 23 26 C 23 21.029 27.029 17 32 17 C 36.971 17 41 21.029 41 26 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 37 26 C 37 28.209 35.209 30 33 30 C 30.791 30 29 28.209 29 26 C 29 23.791 30.791 22 33 22 C 35.209 22 37 23.791 37 26 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: true, fill: true, stroke: 0, round: false, opacity: 1, path: "M 77 26 C 77 30.971 72.971 35 68 35 C 63.029 35 59 30.971 59 26 C 59 21.029 63.029 17 68 17 C 72.971 17 77 21.029 77 26 Z"),
            CharElement(chain: ["root", "look", "eyes"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 73 26 C 73 28.209 71.209 30 69 30 C 66.791 30 65 28.209 65 26 C 65 23.791 66.791 22 69 22 C 71.209 22 73 23.791 73 26 Z"),
        ],
        "frog-limit": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 47 26 C 47 34.284 40.284 41 32 41 C 23.716 41 17 34.284 17 26 C 17 17.716 23.716 11 32 11 C 40.284 11 47 17.716 47 26 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 83 26 C 83 34.284 76.284 41 68 41 C 59.716 41 53 34.284 53 26 C 53 17.716 59.716 11 68 11 C 76.284 11 83 17.716 83 26 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 25 24 C 29.667 30.667 34.333 30.667 39 24"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 61 24 C 65.667 30.667 70.333 30.667 75 24"),
            CharElement(chain: ["zz"], cutout: false, fill: false, stroke: 5.2, round: true, opacity: 1, path: "M 80 0 L 100 0 L 80 20 L 100 20"),
        ],
        "frog-fail": [
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 38 34 C 38 41.732 31.732 48 24 48 C 16.268 48 10 41.732 10 34 C 10 26.268 16.268 20 24 20 C 31.732 20 38 26.268 38 34 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 90 34 C 90 41.732 83.732 48 76 48 C 68.268 48 62 41.732 62 34 C 62 26.268 68.268 20 76 20 C 83.732 20 90 26.268 90 34 Z"),
            CharElement(chain: ["root"], cutout: false, fill: true, stroke: 0, round: false, opacity: 1, path: "M 50 30 C 72 30 84 46 84 62 C 84 74 80 82 78 90 C 78 95.156 73.821 99.335 68.665 99.335 C 63.509 99.335 59.33 95.156 59.33 90 C 59.33 95.153 55.153 99.33 50 99.33 C 44.847 99.33 40.67 95.153 40.67 90 C 40.67 95.156 36.491 99.335 31.335 99.335 C 26.179 99.335 22 95.156 22 90 C 20 82 16 74 16 62 C 16 46 28 30 50 30 Z"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 18 28 L 30 40 M 30 28 L 18 40"),
            CharElement(chain: ["root"], cutout: true, fill: false, stroke: 5.4, round: true, opacity: 1, path: "M 70 28 L 82 40 M 82 28 L 70 40"),
        ],
    ]

    /// "id-state" → グループ名 → 回転・拡大の原点 [x, y]
    static let origins: [String: [String: [Double]]] = [
        "bunny-ok": ["eyes": [50, 60], "look": [50, 60], "root": [50, 99.335]],
        "bunny-limit": ["root": [50, 99.335], "zz": [78, 13]],
        "bunny-fail": ["root": [50, 99.335]],
        "cat-ok": ["eyes": [50, 60], "look": [50, 60], "root": [50, 99.335]],
        "cat-limit": ["root": [50, 99.335], "zz": [78, 13]],
        "cat-fail": ["root": [50, 99.335]],
        "bear-ok": ["eyes": [50, 55], "look": [50, 55], "root": [50, 99.335]],
        "bear-limit": ["root": [50, 99.335], "zz": [78, 13]],
        "bear-fail": ["root": [50, 99.335]],
        "pig-ok": ["eyes": [50, 52], "look": [50, 52], "root": [50, 99.335]],
        "pig-limit": ["root": [50, 99.335], "zz": [78, 13]],
        "pig-fail": ["root": [44, 99.335]],
        "frog-ok": ["eyes": [50, 26], "look": [50, 26], "root": [50, 99.335]],
        "frog-limit": ["root": [50, 99.335], "zz": [90, 10]],
        "frog-fail": ["root": [50, 99.335]],
    ]

    /// characters/motion.json の中身（そのまま）
    static let motionJSON = #"""
{
 "_note": "単位は、SVGのviewBox（0〜100）の座標。translateは座標単位、rotateは度。回転や拡大の原点は、各グループの外枠の下中央（root）または中央（look/eyes/zz）。補間はease-in-out。",
 "canvas": {
  "viewBox": "-6 -6 112 112",
  "menubarHeightPt": 18,
  "maxFps": 8
 },
 "states": {
  "ok": {
   "label": "制限なし",
   "targets": {
    "look": {
     "duration_s": 5,
     "easing": "ease-in-out",
     "keyframes": {
      "0": {
       "translateX": 0
      },
      "15": {
       "translateX": 0
      },
      "25": {
       "translateX": -8
      },
      "45": {
       "translateX": -8
      },
      "55": {
       "translateX": 0
      },
      "60": {
       "translateX": 0
      },
      "70": {
       "translateX": 8
      },
      "90": {
       "translateX": 8
      },
      "100": {
       "translateX": 0
      }
     }
    },
    "root": {
     "duration_s": 5,
     "easing": "ease-in-out",
     "origin": "bottom-center",
     "keyframes": {
      "0": {
       "translateX": 0,
       "rotate": 0
      },
      "15": {
       "translateX": 0,
       "rotate": 0
      },
      "25": {
       "translateX": -3,
       "rotate": -4
      },
      "45": {
       "translateX": -3,
       "rotate": -4
      },
      "55": {
       "translateX": 0,
       "rotate": 0
      },
      "60": {
       "translateX": 0,
       "rotate": 0
      },
      "70": {
       "translateX": 3,
       "rotate": 4
      },
      "90": {
       "translateX": 3,
       "rotate": 4
      },
      "100": {
       "translateX": 0,
       "rotate": 0
      }
     }
    },
    "eyes": {
     "duration_s": 3.4,
     "easing": "linear",
     "origin": "center",
     "keyframes": {
      "0": {
       "scaleY": 1
      },
      "90": {
       "scaleY": 1
      },
      "94": {
       "scaleY": 0.08
      },
      "100": {
       "scaleY": 1
      }
     }
    }
   }
  },
  "limit": {
   "label": "制限中",
   "targets": {
    "root": {
     "duration_s": 3,
     "easing": "ease-in-out",
     "keyframes": {
      "0": {
       "translateY": 0
      },
      "50": {
       "translateY": -9
      },
      "100": {
       "translateY": 0
      }
     }
    },
    "zz": {
     "duration_s": 3,
     "easing": "ease-in-out",
     "origin": "center",
     "keyframes": {
      "0": {
       "opacity": 0.35,
       "translateY": 2
      },
      "50": {
       "opacity": 1,
       "translateY": -2
      },
      "100": {
       "opacity": 0.35,
       "translateY": 2
      }
     }
    }
   }
  },
  "fail": {
   "label": "すべて取得に失敗",
   "targets": {
    "root": {
     "duration_s": 4,
     "easing": "ease-in-out",
     "origin": "bottom-center",
     "keyframes": {
      "0": {
       "rotate": 0
      },
      "88": {
       "rotate": 0
      },
      "91": {
       "rotate": -5
      },
      "94": {
       "rotate": 5
      },
      "97": {
       "rotate": -3
      },
      "100": {
       "rotate": 0
      }
     }
    }
   }
  }
 },
 "reduceMotion": "全部止める（アニメの最初の形で静止）",
 "lowPowerMode": "静止か、まばたき（ok の eyes）だけ",
 "settings": [
  "動く（既定）",
  "ときどきだけ（okのまばたきだけ）",
  "止める"
 ]
}
"""#
}

struct CharElement {
    /// 外側から順に、この部品にかかる動かすグループ（root / look / eyes / zz）
    let chain: [String]
    /// 「抜き」（透明にくり抜く）
    let cutout: Bool
    let fill: Bool
    /// 線の太さ（0 なら線なし）
    let stroke: Double
    /// 線の端と角を丸くする
    let round: Bool
    let opacity: Double
    /// M / L / C / Z だけの絶対座標のパス（viewBox は -6 -6 112 112）
    let path: String
}
