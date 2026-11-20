/// Versioned KeSIC 2020 reference, transcribed from the first-edition 2021
/// official standard. The app profile is independent from economic activity.
/// Code 016190 is excluded because the official standard and correspondence
/// tables assign it conflicting descriptions. User-entered codes remain pending.
/// Reference source: KLMIS / Ministry of Labour, PDFs linked below.
class KeSicActivity {
  const KeSicActivity(this.code, this.label, this.breadcrumb);
  final String code;
  final String label;
  final String breadcrumb;
}

const kesicReferenceVersion = 'KeSIC-2020-First-Edition-2021';
const kesicReferenceSource =
    'https://kesic.labourmarket.go.ke/kesic-classic-segments/';
const kesicOfficialStandard =
    'https://www.labour.go.ke/sites/default/files/2022-10/PRINT-COPY-OF-KESIC-STANDARD.pdf';
const kesicCorrespondenceTables =
    'https://labour.go.ke/sites/default/files/2022-10/KESIC-CORREPONDENCE-TABLES-PRINT-VERSON.pdf';
const kesicAmbiguousCodes = <String>{'016190'};

const kesicActivities = <KeSicActivity>[
  KeSicActivity(
      "011000",
      "Mixed cropping of Non-Perennial Crops",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0110 · Mixed cropping of Non-Perennial Crops / Subclass 01100 · Mixed cropping of Non-Perennial Crops",
  ),
  KeSicActivity(
      "011111",
      "Growing of maize",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01111 · Growing of cereals (except rice)",
  ),
  KeSicActivity(
      "011112",
      "Growing of wheat",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01111 · Growing of cereals (except rice)",
  ),
  KeSicActivity(
      "011113",
      "Growing of sorghum",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01111 · Growing of cereals (except rice)",
  ),
  KeSicActivity(
      "011114",
      "Growing of Millet",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01111 · Growing of cereals (except rice)",
  ),
  KeSicActivity(
      "011115",
      "Growing of Barley",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01111 · Growing of cereals (except rice)",
  ),
  KeSicActivity(
      "011116",
      "Growing of mixed cereals",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01111 · Growing of cereals (except rice)",
  ),
  KeSicActivity(
      "011117",
      "Growing of cereal seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01111 · Growing of cereals (except rice)",
  ),
  KeSicActivity(
      "011119",
      "Growing of Other cereals",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01111 · Growing of cereals (except rice)",
  ),
  KeSicActivity(
      "011121",
      "Growing of Beans",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011122",
      "Growing of Green grams",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011123",
      "Growing of Cow peas",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011124",
      "Growing of Dolichos",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011125",
      "Growing of Green peas",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011126",
      "Growing of french beans",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011127",
      "Growing of mixed leguminous crops",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011128",
      "Growing of leguminous crop seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011129",
      "Growing of Other leguminous crops",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01112 · Growing of leguminous crops",
  ),
  KeSicActivity(
      "011131",
      "Growing of groundnuts",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01113 · Growing of oil seeds",
  ),
  KeSicActivity(
      "011132",
      "Growing of sunflower seed",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01113 · Growing of oil seeds",
  ),
  KeSicActivity(
      "011133",
      "Growing of sesame seed",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01113 · Growing of oil seeds",
  ),
  KeSicActivity(
      "011134",
      "Growing of soya beans",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01113 · Growing of oil seeds",
  ),
  KeSicActivity(
      "011135",
      "Growing of mixed oil seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01113 · Growing of oil seeds",
  ),
  KeSicActivity(
      "011139",
      "Growing of other oil seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0111 · Growing of cereals (except rice), leguminous crops and oil seeds / Subclass 01113 · Growing of oil seeds",
  ),
  KeSicActivity(
      "011201",
      "Growing of rice",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0112 · Growing of rice / Subclass 01120 · Growing of rice",
  ),
  KeSicActivity(
      "011202",
      "Growing of rice seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0112 · Growing of rice / Subclass 01120 · Growing of rice",
  ),
  KeSicActivity(
      "011311",
      "Growing of Cabbages",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011312",
      "Growing of Spinach",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011313",
      "Growing of cauliflower and broccoli",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011314",
      "Growing of Lettuce and related vegetables",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011315",
      "Growing of snow peas",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011316",
      "Growing of kale",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011317",
      "Growing of indigenous leafy or stem vegetables( e.g. saga,managu, etc)",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011318",
      "Growing of leafy or stem vegetables seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011319",
      "Growing of other leafy or stem vegetables",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01131 · Growing of leafy or stem vegetables",
  ),
  KeSicActivity(
      "011321",
      "Growing of tomatoes",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01132 · Growing of fruit bearing vegetables",
  ),
  KeSicActivity(
      "011322",
      "Growing of cucumbers and gherkins",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01132 · Growing of fruit bearing vegetables",
  ),
  KeSicActivity(
      "011323",
      "Growing of Watermelon",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01132 · Growing of fruit bearing vegetables",
  ),
  KeSicActivity(
      "011324",
      "Growing of eggplants",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01132 · Growing of fruit bearing vegetables",
  ),
  KeSicActivity(
      "011325",
      "Growing of mixed fruit bearing vegetables",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01132 · Growing of fruit bearing vegetables",
  ),
  KeSicActivity(
      "011326",
      "Growing of fruit bearing vegetables seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01132 · Growing of fruit bearing vegetables",
  ),
  KeSicActivity(
      "011329",
      "Growing of other fruit bearing vegetables",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01132 · Growing of fruit bearing vegetables",
  ),
  KeSicActivity(
      "011330",
      "Growing of mixed leafy or stem and fruit bearing vegetables",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01133 · Growing of mixed leafy or stem and fruit bearing vegetables",
  ),
  KeSicActivity(
      "011341",
      "Growing of carrots",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01134 · Growing of root, bulb or tuberous vegetables",
  ),
  KeSicActivity(
      "011342",
      "Growing of bulb onions",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01134 · Growing of root, bulb or tuberous vegetables",
  ),
  KeSicActivity(
      "011343",
      "Growing of leeks",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01134 · Growing of root, bulb or tuberous vegetables",
  ),
  KeSicActivity(
      "011344",
      "Growing of garlic",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01134 · Growing of root, bulb or tuberous vegetables",
  ),
  KeSicActivity(
      "011345",
      "Growing of root, bulb or tuberous vegetables seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01134 · Growing of root, bulb or tuberous vegetables",
  ),
  KeSicActivity(
      "011349",
      "Growing of other root, bulb or tuberous vegetables",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01134 · Growing of root, bulb or tuberous vegetables",
  ),
  KeSicActivity(
      "011350",
      "Growing of mushrooms and truffles",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01135 · Growing of mushrooms and truffles",
  ),
  KeSicActivity(
      "011361",
      "Growing of potatoes",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01136 · Growing of roots and tubers",
  ),
  KeSicActivity(
      "011362",
      "Growing of cassava",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01136 · Growing of roots and tubers",
  ),
  KeSicActivity(
      "011363",
      "Growing of sweet potatoes",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01136 · Growing of roots and tubers",
  ),
  KeSicActivity(
      "011364",
      "Growing of mixed roots and tubers",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01136 · Growing of roots and tubers",
  ),
  KeSicActivity(
      "011369",
      "Growing of other roots and tubers",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01136 · Growing of roots and tubers",
  ),
  KeSicActivity(
      "011370",
      "Growing of mixed vegetables",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0113 · Growing of vegetables and melons, roots and tubers / Subclass 01137 · Growing of mixed vegetables",
  ),
  KeSicActivity(
      "011400",
      "Growing of sugar cane",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0114 · Growing of sugar cane / Subclass 01140 · Growing of sugar cane",
  ),
  KeSicActivity(
      "011500",
      "Growing of tobacco",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0115 · Growing of tobacco / Subclass 01150 · Growing of tobacco",
  ),
  KeSicActivity(
      "011601",
      "Growing of cotton",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0116 · Growing of fibre crops (Except Sisal) / Subclass 01160 · Growing of fibre crops (Except Sisal)",
  ),
  KeSicActivity(
      "011602",
      "Growing of cotton seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0116 · Growing of fibre crops (Except Sisal) / Subclass 01160 · Growing of fibre crops (Except Sisal)",
  ),
  KeSicActivity(
      "011609",
      "Growing of other fibre crops(except sisal)",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0116 · Growing of fibre crops (Except Sisal) / Subclass 01160 · Growing of fibre crops (Except Sisal)",
  ),
  KeSicActivity(
      "011911",
      "Growing of fodder crops",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0119 · Growing of other non-perennial crops / Subclass 01191 · Growing of fodder crops and crop seeds",
  ),
  KeSicActivity(
      "011912",
      "Growing of fodder crops seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0119 · Growing of other non-perennial crops / Subclass 01191 · Growing of fodder crops and crop seeds",
  ),
  KeSicActivity(
      "011921",
      "Growing of flowers, including production of cut flowers and flower buds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0119 · Growing of other non-perennial crops / Subclass 01192 · Growing of flowers, including production of cut flowers and flower buds",
  ),
  KeSicActivity(
      "011922",
      "Growing of flowers seeds",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0119 · Growing of other non-perennial crops / Subclass 01192 · Growing of flowers, including production of cut flowers and flower buds",
  ),
  KeSicActivity(
      "011990",
      "Growing of other non-perennial crops",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 011 · Growing of non-perennial crops / Class 0119 · Growing of other non-perennial crops / Subclass 01199 · Growing of other non-perennial crops",
  ),
  KeSicActivity(
      "012000",
      "Growing of coffee",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0120 · Growing of coffee / Subclass 01200 · Growing of coffee",
  ),
  KeSicActivity(
      "012100",
      "Growing of grapes",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0121 · Growing of grapes / Subclass 01210 · Growing of grapes",
  ),
  KeSicActivity(
      "012201",
      "Growing of bananas",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0122 · Growing of tropical and subtropical fruits / Subclass 01220 · Growing of tropical and subtropical fruits",
  ),
  KeSicActivity(
      "012202",
      "Growing of mangoes",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0122 · Growing of tropical and subtropical fruits / Subclass 01220 · Growing of tropical and subtropical fruits",
  ),
  KeSicActivity(
      "012203",
      "Growing of pineapples",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0122 · Growing of tropical and subtropical fruits / Subclass 01220 · Growing of tropical and subtropical fruits",
  ),
  KeSicActivity(
      "012204",
      "Growing of avocado",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0122 · Growing of tropical and subtropical fruits / Subclass 01220 · Growing of tropical and subtropical fruits",
  ),
  KeSicActivity(
      "012205",
      "Growing of pawpaw",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0122 · Growing of tropical and subtropical fruits / Subclass 01220 · Growing of tropical and subtropical fruits",
  ),
  KeSicActivity(
      "012206",
      "Growing of mixed tropical and subtropical fruits",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0122 · Growing of tropical and subtropical fruits / Subclass 01220 · Growing of tropical and subtropical fruits",
  ),
  KeSicActivity(
      "012209",
      "Growing of other tropical and subtropical fruits",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0122 · Growing of tropical and subtropical fruits / Subclass 01220 · Growing of tropical and subtropical fruits",
  ),
  KeSicActivity(
      "012301",
      "Growing of oranges",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0123 · Growing of citrus fruits / Subclass 01230 · Growing of citrus fruits",
  ),
  KeSicActivity(
      "012302",
      "Growing of lemons and lime",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0123 · Growing of citrus fruits / Subclass 01230 · Growing of citrus fruits",
  ),
  KeSicActivity(
      "012309",
      "Growing of other citrus fruits",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0123 · Growing of citrus fruits / Subclass 01230 · Growing of citrus fruits",
  ),
  KeSicActivity(
      "012401",
      "Growing of pears",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0124 · Growing of pome fruits and stone fruits / Subclass 01240 · Growing of pome fruits and stone fruits",
  ),
  KeSicActivity(
      "012402",
      "Growing of plums",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0124 · Growing of pome fruits and stone fruits / Subclass 01240 · Growing of pome fruits and stone fruits",
  ),
  KeSicActivity(
      "012409",
      "Growing of other pome fruits and stone fruits",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0124 · Growing of pome fruits and stone fruits / Subclass 01240 · Growing of pome fruits and stone fruits",
  ),
  KeSicActivity(
      "012511",
      "Growing of blue berries",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0125 · Growing of other tree and bush fruits and nuts / Subclass 01251 · Growing of berries",
  ),
  KeSicActivity(
      "012512",
      "Growing of strawberries",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0125 · Growing of other tree and bush fruits and nuts / Subclass 01251 · Growing of berries",
  ),
  KeSicActivity(
      "012519",
      "Growing of other berries",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0125 · Growing of other tree and bush fruits and nuts / Subclass 01251 · Growing of berries",
  ),
  KeSicActivity(
      "012531",
      "Growing of macadamia",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0125 · Growing of other tree and bush fruits and nuts / Subclass 01253 · Growing of nuts excluding coconuts",
  ),
  KeSicActivity(
      "012532",
      "Growing of cashewnuts",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0125 · Growing of other tree and bush fruits and nuts / Subclass 01253 · Growing of nuts excluding coconuts",
  ),
  KeSicActivity(
      "012539",
      "Growing of other nuts",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0125 · Growing of other tree and bush fruits and nuts / Subclass 01253 · Growing of nuts excluding coconuts",
  ),
  KeSicActivity(
      "012540",
      "Growing of other tree and bush fruits",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0125 · Growing of other tree and bush fruits and nuts / Subclass 01254 · Growing of other tree and bush fruits",
  ),
  KeSicActivity(
      "012601",
      "Growing of coconut",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0126 · Growing of oleaginous fruits / Subclass 01260 · Growing of oleaginous fruits excluding soya beans, groundnuts and other oil seeds",
  ),
  KeSicActivity(
      "012609",
      "Growing of other oleaginous fruits",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0126 · Growing of oleaginous fruits / Subclass 01260 · Growing of oleaginous fruits excluding soya beans, groundnuts and other oil seeds",
  ),
  KeSicActivity(
      "012710",
      "Growing of tea",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0127 · Growing of tea / Subclass 01271 · Growing of tea",
  ),
  KeSicActivity(
      "012790",
      "Growing of other beverage crops",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0127 · Growing of tea / Subclass 01279 · Growing of other beverage crops",
  ),
  KeSicActivity(
      "012811",
      "Growing of chilies",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0128 · Growing of spices, aromatic, drug and pharmaceutical crops / Subclass 01281 · Growing of spices and aromatic crops",
  ),
  KeSicActivity(
      "012812",
      "Growing of capsicum",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0128 · Growing of spices, aromatic, drug and pharmaceutical crops / Subclass 01281 · Growing of spices and aromatic crops",
  ),
  KeSicActivity(
      "012813",
      "Growing of ginger",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0128 · Growing of spices, aromatic, drug and pharmaceutical crops / Subclass 01281 · Growing of spices and aromatic crops",
  ),
  KeSicActivity(
      "012819",
      "Other spices and aromatic crops e.g. Basil , Rosemary, Celery",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0128 · Growing of spices, aromatic, drug and pharmaceutical crops / Subclass 01281 · Growing of spices and aromatic crops",
  ),
  KeSicActivity(
      "012820",
      "Growing of drug and pharmaceutical crops except pyrethrum",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0128 · Growing of spices, aromatic, drug and pharmaceutical crops / Subclass 01282 · Growing of drug and pharmaceutical crops except pyrethrum",
  ),
  KeSicActivity(
      "012830",
      "Growing of Pyrethrum",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0128 · Growing of spices, aromatic, drug and pharmaceutical crops / Subclass 01283 · Growing of Pyrethrum",
  ),
  KeSicActivity(
      "012910",
      "Growing of Khat \"Miraa\"",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0129 · Growing of other perennial crops / Subclass 01291 · Growing of Khat \"Miraa\"",
  ),
  KeSicActivity(
      "012990",
      "Growing of other perennial crops",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 012 · Growing of perennial crops / Class 0129 · Growing of other perennial crops / Subclass 01299 · Growing of other perennial crops",
  ),
  KeSicActivity(
      "013010",
      "Operation of tree nurseries, except forest tree nurseries",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 013 · Plant propagation / Class 0130 · Plant propagation / Subclass 01301 · Operation of tree nurseries, except forest tree nurseries",
  ),
  KeSicActivity(
      "013020",
      "Growing of plants for planting",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 013 · Plant propagation / Class 0130 · Plant propagation / Subclass 01302 · Growing of plants for planting",
  ),
  KeSicActivity(
      "013030",
      "Mixed plant propagation",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 013 · Plant propagation / Class 0130 · Plant propagation / Subclass 01303 · Mixed plant propagation",
  ),
  KeSicActivity(
      "013090",
      "Other plant propagation",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 013 · Plant propagation / Class 0130 · Plant propagation / Subclass 01309 · Other plant propagation",
  ),
  KeSicActivity(
      "014000",
      "Mixed animal farming",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0140 · Mixed animal farming / Subclass 01400 · Mixed animal farming",
  ),
  KeSicActivity(
      "014110",
      "Raising and breeding of cattle",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0141 · Raising of cattle and buffaloes / Subclass 01411 · Raising and breeding of cattle",
  ),
  KeSicActivity(
      "014120",
      "Dairy farming-Cattle",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0141 · Raising of cattle and buffaloes / Subclass 01412 · Dairy farming-Cattle",
  ),
  KeSicActivity(
      "014130",
      "Production of bovine semen",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0141 · Raising of cattle and buffaloes / Subclass 01413 · Production of bovine semen",
  ),
  KeSicActivity(
      "014200",
      "Raising of horses and other equines",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0142 · Raising of horses and other equines / Subclass 01420 · Raising of horses and other equines",
  ),
  KeSicActivity(
      "014310",
      "Raising of camels",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0143 · Raising of camels and camelids / Subclass 01431 · Raising of camels",
  ),
  KeSicActivity(
      "014320",
      "Production of camel milk",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0143 · Raising of camels and camelids / Subclass 01432 · Production of camel milk",
  ),
  KeSicActivity(
      "014410",
      "Raising and breeding of goats",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0144 · Raising of sheep and goats / Subclass 01441 · Raising and breeding of goats",
  ),
  KeSicActivity(
      "014420",
      "Raising and breeding of sheep",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0144 · Raising of sheep and goats / Subclass 01442 · Raising and breeding of sheep",
  ),
  KeSicActivity(
      "014430",
      "Dairy farming-Goat",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0144 · Raising of sheep and goats / Subclass 01443 · Dairy farming-Goat",
  ),
  KeSicActivity(
      "014440",
      "Production of raw wool",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0144 · Raising of sheep and goats / Subclass 01444 · Production of raw wool",
  ),
  KeSicActivity(
      "014500",
      "Raising of swine/pigs",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0145 · Raising of swine/pigs / Subclass 01450 · Raising of swine/pigs",
  ),
  KeSicActivity(
      "014611",
      "Raising and breeding of chicken",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0146 · Raising of poultry / Subclass 01461 · Raising and breeding of poultry",
  ),
  KeSicActivity(
      "014619",
      "Raising and breeding of other poultry",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0146 · Raising of poultry / Subclass 01461 · Raising and breeding of poultry",
  ),
  KeSicActivity(
      "014621",
      "Production of chicken eggs",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0146 · Raising of poultry / Subclass 01462 · Production of eggs",
  ),
  KeSicActivity(
      "014629",
      "Production of other poultry eggs",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0146 · Raising of poultry / Subclass 01462 · Production of eggs",
  ),
  KeSicActivity(
      "014631",
      "Operation of chicken hatcheries",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0146 · Raising of poultry / Subclass 01463 · Operation of poultry hatcheries",
  ),
  KeSicActivity(
      "014639",
      "Operation of other poultry hatcheries",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0146 · Raising of poultry / Subclass 01463 · Operation of poultry hatcheries",
  ),
  KeSicActivity(
      "014700",
      "Bee-keeping and production of honey and beeswax",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0147 · Bee-keeping and production of honey and beeswax / Subclass 01470 · Bee-keeping and production of honey and beeswax",
  ),
  KeSicActivity(
      "014910",
      "Raising of silk worms, production of silk worm cocoons",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0149 · Raising of other animals / Subclass 01491 · Raising of silk worms, production of silk worm cocoons",
  ),
  KeSicActivity(
      "014921",
      "Raising and breeding of ostriches and emus",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0149 · Raising of other animals / Subclass 01492 · Raising and breeding of semi-domesticated or other live animals:",
  ),
  KeSicActivity(
      "014922",
      "Raising and breeding of other birds except poultry",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0149 · Raising of other animals / Subclass 01492 · Raising and breeding of semi-domesticated or other live animals:",
  ),
  KeSicActivity(
      "014923",
      "Raising and breeding of Rabbits and other fur animals",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0149 · Raising of other animals / Subclass 01492 · Raising and breeding of semi-domesticated or other live animals:",
  ),
  KeSicActivity(
      "014931",
      "Raising and breeding of dogs",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0149 · Raising of other animals / Subclass 01493 · Raising and breeding of pet animals",
  ),
  KeSicActivity(
      "014939",
      "Raising and breeding of other pet animals",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0149 · Raising of other animals / Subclass 01493 · Raising and breeding of pet animals",
  ),
  KeSicActivity(
      "014990",
      "Raising of other animals",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 014 · Animal production / Class 0149 · Raising of other animals / Subclass 01499 · Raising of other animals",
  ),
  KeSicActivity(
      "015000",
      "Mixed farming",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 015 · Mixed farming / Class 0150 · Mixed farming / Subclass 01500 · Mixed farming",
  ),
  KeSicActivity(
      "016111",
      "Preparation of fields",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0161 · Support activities for crop production / Subclass 01611 · Agricultural activities on a fee or contract basis",
  ),
  KeSicActivity(
      "016112",
      "Establishing a crop",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0161 · Support activities for crop production / Subclass 01611 · Agricultural activities on a fee or contract basis",
  ),
  KeSicActivity(
      "016113",
      "Crop spraying, including by air",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0161 · Support activities for crop production / Subclass 01611 · Agricultural activities on a fee or contract basis",
  ),
  KeSicActivity(
      "016114",
      "Harvesting",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0161 · Support activities for crop production / Subclass 01611 · Agricultural activities on a fee or contract basis",
  ),
  KeSicActivity(
      "016119",
      "Other agricultural activities on a fee or contract basis",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0161 · Support activities for crop production / Subclass 01611 · Agricultural activities on a fee or contract basis",
  ),
  KeSicActivity(
      "016120",
      "Provision of agricultural machinery with operators and crew",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0161 · Support activities for crop production / Subclass 01612 · Provision of agricultural machinery with operators and crew",
  ),
  KeSicActivity(
      "016211",
      "Activities related to artificial insemination",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0162 · Support activities for animal production / Subclass 01621 · Agricultural activities on a fee or contract basis",
  ),
  KeSicActivity(
      "016212",
      "Sheep shearing",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0162 · Support activities for animal production / Subclass 01621 · Agricultural activities on a fee or contract basis",
  ),
  KeSicActivity(
      "016219",
      "Other agricultural activities on a fee or contract basis",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0162 · Support activities for animal production / Subclass 01621 · Agricultural activities on a fee or contract basis",
  ),
  KeSicActivity(
      "016310",
      "Preparation of crops for primary markets, i.e. cleaning, trimming, grading, disinfecting",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0163 · Post-harvest crop activities / Subclass 01631 · Preparation of crops for primary markets, i.e. cleaning, trimming, grading, disinfecting",
  ),
  KeSicActivity(
      "016320",
      "Cotton ginning",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0163 · Post-harvest crop activities / Subclass 01632 · Cotton ginning",
  ),
  KeSicActivity(
      "016330",
      "Preparation of tobacco leaves",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0163 · Post-harvest crop activities / Subclass 01633 · Preparation of tobacco leaves",
  ),
  KeSicActivity(
      "016340",
      "Waxing of fruit",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0163 · Post-harvest crop activities / Subclass 01634 · Waxing of fruit",
  ),
  KeSicActivity(
      "016350",
      "Sun-drying of fruit and vegetables",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0163 · Post-harvest crop activities / Subclass 01635 · Sun-drying of fruit and vegetables",
  ),
  KeSicActivity(
      "016390",
      "Other Post-harvest crop activities",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0163 · Post-harvest crop activities / Subclass 01639 · Other Post-harvest crop activities",
  ),
  KeSicActivity(
      "016400",
      "Seed processing for propagation",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 016 · Support activities to agriculture and post- harvest crop activities / Class 0164 · Seed processing for propagation / Subclass 01640 · Seed processing for propagation",
  ),
  KeSicActivity(
      "017000",
      "Hunting, trapping and related service activities",
      "Section A · Agriculture, forestry and fishing / Division 01 · Crop and animal production, hunting and related service activities / Group 017 · Hunting, trapping and related service activities / Class 0170 · Hunting, trapping and related service activities / Subclass 01700 · Hunting, trapping and related service activities",
  ),
  KeSicActivity(
      "021010",
      "Growing of standing timber: planting, replanting, transplanting, thinning and conserving of forests and timber tracts",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Group 021 · Silviculture and other forestry activities / Class 0210 · Silviculture and other forestry activities / Subclass 02101 · Growing of standing timber: planting, replanting, transplanting, thinning and conserving of forests and timber tracts",
  ),
  KeSicActivity(
      "021020",
      "Growing of coppice, pulpwood and firewood",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Group 021 · Silviculture and other forestry activities / Class 0210 · Silviculture and other forestry activities / Subclass 02102 · Growing of coppice, pulpwood and firewood",
  ),
  KeSicActivity(
      "021030",
      "Operation of forest tree nurseries",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Group 021 · Silviculture and other forestry activities / Class 0210 · Silviculture and other forestry activities / Subclass 02103 · Operation of forest tree nurseries",
  ),
  KeSicActivity(
      "021090",
      "Other silviculture and other forestry activities",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Group 021 · Silviculture and other forestry activities / Class 0210 · Silviculture and other forestry activities / Subclass 02109 · Other silviculture and other forestry activities",
  ),
  KeSicActivity(
      "022100",
      "Production of roundwood for forest-based manufacturing industries",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Group 022 · Logging / Class 0221 · Production of roundwood for forest-based manufacturing industries / Subclass 02210 · Production of roundwood for forest-based manufacturing industries",
  ),
  KeSicActivity(
      "022200",
      "Production of roundwood used in an unprocessed form such as pit-props, fence posts and utility poles",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Group 022 · Logging / Class 0222 · Production of roundwood used in an unprocessed form such as pit-props, fence posts and utility poles / Subclass 02220 · Production of roundwood used in an unprocessed form such as pit-props, fence posts and utility poles",
  ),
  KeSicActivity(
      "022300",
      "Gathering and production of fire wood",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Group 022 · Logging / Class 0223 · Gathering and production of fire wood / Subclass 02230 · Gathering and production of fire wood",
  ),
  KeSicActivity(
      "022400",
      "Production of charcoal in the forest (using traditional methods)",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Group 022 · Logging / Class 0224 · Production of charcoal in the forest (using traditional methods) / Subclass 02240 · Production of charcoal in the forest (using traditional methods)",
  ),
  KeSicActivity(
      "023000",
      "Gathering of non-wood forest products",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Class 0230 · Gathering of non-wood forest products / Subclass 02300 · Gathering of non-wood forest products",
  ),
  KeSicActivity(
      "024011",
      "Forestry inventories",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Class 0240 · support services to forestry / Subclass 02401 · Forestry service activities",
  ),
  KeSicActivity(
      "024012",
      "Forest management consulting services",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Class 0240 · support services to forestry / Subclass 02401 · Forestry service activities",
  ),
  KeSicActivity(
      "024013",
      "Timber evaluation",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Class 0240 · support services to forestry / Subclass 02401 · Forestry service activities",
  ),
  KeSicActivity(
      "024014",
      "Forest fire fighting and protection",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Class 0240 · support services to forestry / Subclass 02401 · Forestry service activities",
  ),
  KeSicActivity(
      "024015",
      "Forest pest control",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Class 0240 · support services to forestry / Subclass 02401 · Forestry service activities",
  ),
  KeSicActivity(
      "024021",
      "Transport of logs within the forest",
      "Section A · Agriculture, forestry and fishing / Division 02 · Forestry and logging / Class 0240 · support services to forestry / Subclass 02402 · Logging service activities",
  ),
  KeSicActivity(
      "031110",
      "Fishing on a commercial basis in ocean and coastal waters",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 031 · Fishing / Class 0311 · Marine fishing / Subclass 03111 · Fishing on a commercial basis in ocean and coastal waters",
  ),
  KeSicActivity(
      "031120",
      "Taking of marine crustaceans and molluscs",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 031 · Fishing / Class 0311 · Marine fishing / Subclass 03112 · Taking of marine crustaceans and molluscs",
  ),
  KeSicActivity(
      "031190",
      "Other marine fishing",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 031 · Fishing / Class 0311 · Marine fishing / Subclass 03119 · Other marine fishing",
  ),
  KeSicActivity(
      "031210",
      "Fishing on a commercial basis in inland waters",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 031 · Fishing / Class 0312 · Freshwater fishing / Subclass 03121 · Fishing on a commercial basis in inland waters",
  ),
  KeSicActivity(
      "031290",
      "Other freshwater fishing",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 031 · Fishing / Class 0312 · Freshwater fishing / Subclass 03129 · Other freshwater fishing",
  ),
  KeSicActivity(
      "032100",
      "Marine aquaculture",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 032 · Aquaculture / Class 0321 · Marine aquaculture / Subclass 03210 · Marine aquaculture",
  ),
  KeSicActivity(
      "032210",
      "Fish farming in freshwater including farming of freshwater ornamental fish",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 032 · Aquaculture / Class 0322 · Freshwater aquaculture / Subclass 03221 · Fish farming in freshwater including farming of freshwater ornamental fish",
  ),
  KeSicActivity(
      "032220",
      "Operation of fish hatcheries (freshwater)",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 032 · Aquaculture / Class 0322 · Freshwater aquaculture / Subclass 03222 · Operation of fish hatcheries (freshwater)",
  ),
  KeSicActivity(
      "032290",
      "Other freshwater aquaculture",
      "Section A · Agriculture, forestry and fishing / Division 03 · Fishing and Aquaculture / Group 032 · Aquaculture / Class 0322 · Freshwater aquaculture / Subclass 03229 · Other freshwater aquaculture",
  ),
  KeSicActivity(
      "051000",
      "Mining of hard coal",
      "Section B · Mining and quarrying / Division 05 · Mining of coal and lignite / Group 051 · Mining of hard coal / Class 0510 · Mining of hard coal / Subclass 05100 · Mining of hard coal",
  ),
  KeSicActivity(
      "052000",
      "Mining of lignite",
      "Section B · Mining and quarrying / Division 05 · Mining of coal and lignite / Group 052 · Mining of lignite / Class 0520 · Mining of lignite / Subclass 05200 · Mining of lignite",
  ),
  KeSicActivity(
      "061000",
      "Extraction of crude petroleum",
      "Section B · Mining and quarrying / Division 06 · Extraction of crude petroleum and natural gas / Group 061 · Extraction of crude petroleum / Class 0610 · Extraction of crude petroleum / Subclass 06100 · Extraction of crude petroleum",
  ),
  KeSicActivity(
      "062100",
      "Extraction of natural gas",
      "Section B · Mining and quarrying / Division 06 · Extraction of crude petroleum and natural gas / Group 062 · Extraction of natural gas / Class 0621 · Extraction of natural gas / Subclass 06210 · Extraction of natural gas",
  ),
  KeSicActivity(
      "062200",
      "Extraction of carbon dioxide",
      "Section B · Mining and quarrying / Division 06 · Extraction of crude petroleum and natural gas / Group 062 · Extraction of natural gas / Class 0622 · Extraction of carbon dioxide / Subclass 06220 · Extraction of carbon dioxide",
  ),
  KeSicActivity(
      "071000",
      "Mining of iron ores",
      "Section B · Mining and quarrying / Division 07 · M Mining of metal ores / Group 071 · Mining of iron ores / Class 0710 · Mining of iron ores / Subclass 07100 · Mining of iron ores",
  ),
  KeSicActivity(
      "072100",
      "Mining of uranium and thorium ores",
      "Section B · Mining and quarrying / Division 07 · M Mining of metal ores / Group 072 · Mining of non-ferrous metal ores / Class 0721 · Mining of uranium and thorium ores / Subclass 07210 · Mining of uranium and thorium ores",
  ),
  KeSicActivity(
      "072210",
      "Mining of ilmenite",
      "Section B · Mining and quarrying / Division 07 · M Mining of metal ores / Group 072 · Mining of non-ferrous metal ores / Class 0722 · Mining of titanium ore minerals / Subclass 07221 · Mining of ilmenite",
  ),
  KeSicActivity(
      "072220",
      "Mining of rutile",
      "Section B · Mining and quarrying / Division 07 · M Mining of metal ores / Group 072 · Mining of non-ferrous metal ores / Class 0722 · Mining of titanium ore minerals / Subclass 07222 · Mining of rutile",
  ),
  KeSicActivity(
      "072230",
      "Mining of zircon",
      "Section B · Mining and quarrying / Division 07 · M Mining of metal ores / Group 072 · Mining of non-ferrous metal ores / Class 0722 · Mining of titanium ore minerals / Subclass 07223 · Mining of zircon",
  ),
  KeSicActivity(
      "072300",
      "Mining of manganese ore",
      "Section B · Mining and quarrying / Division 07 · M Mining of metal ores / Group 072 · Mining of non-ferrous metal ores / Class 0723 · Mining of manganese ore / Subclass 07230 · Mining of manganese ore",
  ),
  KeSicActivity(
      "072400",
      "Mining of gold",
      "Section B · Mining and quarrying / Division 07 · M Mining of metal ores / Group 072 · Mining of non-ferrous metal ores / Class 0724 · Mining of gold / Subclass 07240 · Mining of gold",
  ),
  KeSicActivity(
      "072900",
      "Mining of other non-ferrous metal ores",
      "Section B · Mining and quarrying / Division 07 · M Mining of metal ores / Group 072 · Mining of non-ferrous metal ores / Class 0729 · Mining of other non-ferrous metal ores / Subclass 07290 · Mining of other non-ferrous metal ores",
  ),
  KeSicActivity(
      "081011",
      "Quarrying of stone",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 081 · Quarrying of stone, sand and clay / Class 0810 · Quarrying of stone, sand and clay / Subclass 08101 · Quarrying of stone",
  ),
  KeSicActivity(
      "081012",
      "Quarrying of monumental stone (mazeras, granite e.g. galana stone, Machakos silver stone, quartzite etc)",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 081 · Quarrying of stone, sand and clay / Class 0810 · Quarrying of stone, sand and clay / Subclass 08101 · Quarrying of stone",
  ),
  KeSicActivity(
      "081020",
      "Sand harvesting",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 081 · Quarrying of stone, sand and clay / Class 0810 · Quarrying of stone, sand and clay / Subclass 08102 · Sand harvesting",
  ),
  KeSicActivity(
      "081091",
      "Mining of gypsum and anhydrite",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 081 · Quarrying of stone, sand and clay / Class 0810 · Quarrying of stone, sand and clay / Subclass 08109 · Other quarrying such as clay extraction",
  ),
  KeSicActivity(
      "081092",
      "Breaking and crushing of stone and gravel",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 081 · Quarrying of stone, sand and clay / Class 0810 · Quarrying of stone, sand and clay / Subclass 08109 · Other quarrying such as clay extraction",
  ),
  KeSicActivity(
      "081093",
      "Quarrying, crushing and breaking of limestone",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 081 · Quarrying of stone, sand and clay / Class 0810 · Quarrying of stone, sand and clay / Subclass 08109 · Other quarrying such as clay extraction",
  ),
  KeSicActivity(
      "081094",
      "Mining of clays, refractory clays and kaolin",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 081 · Quarrying of stone, sand and clay / Class 0810 · Quarrying of stone, sand and clay / Subclass 08109 · Other quarrying such as clay extraction",
  ),
  KeSicActivity(
      "081099",
      "Other quarrying such as clay extraction",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 081 · Quarrying of stone, sand and clay / Class 0810 · Quarrying of stone, sand and clay / Subclass 08109 · Other quarrying such as clay extraction",
  ),
  KeSicActivity(
      "089100",
      "Mining of chemical and fertilizer minerals",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 089 · Mining and quarrying n.e.c / Class 0891 · Mining of chemical and fertilizer minerals / Subclass 08910 · Mining of chemical and fertilizer minerals",
  ),
  KeSicActivity(
      "089200",
      "Extraction of peat",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 089 · Mining and quarrying n.e.c / Class 0892 · Extraction of peat / Subclass 08920 · Extraction of peat",
  ),
  KeSicActivity(
      "089300",
      "Extraction of salt",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 089 · Mining and quarrying n.e.c / Class 0893 · Extraction of salt / Subclass 08930 · Extraction of salt",
  ),
  KeSicActivity(
      "089400",
      "Extraction of soda ash",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 089 · Mining and quarrying n.e.c / Class 0894 · Extraction of soda ash / Subclass 08940 · Extraction of soda ash",
  ),
  KeSicActivity(
      "089500",
      "Extraction of fluorspar",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 089 · Mining and quarrying n.e.c / Class 0895 · Extraction of fluorspar / Subclass 08950 · Extraction of fluorspar",
  ),
  KeSicActivity(
      "089600",
      "Extraction of diatomite",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 089 · Mining and quarrying n.e.c / Class 0896 · Extraction of diatomite / Subclass 08960 · Extraction of diatomite",
  ),
  KeSicActivity(
      "089700",
      "Extraction of gem stones",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 089 · Mining and quarrying n.e.c / Class 0897 · Extraction of gem stones / Subclass 08970 · Extraction of gem stones",
  ),
  KeSicActivity(
      "089900",
      "Other mining and quarrying n.e.c",
      "Section B · Mining and quarrying / Division 08 · Other mining and quarrying / Group 089 · Mining and quarrying n.e.c / Class 0899 · Other mining and quarrying n.e.c. This class includes mining and quarrying of various minerals and materials / Subclass 08990 · Other mining and quarrying n.e.c",
  ),
  KeSicActivity(
      "091011",
      "Test drilling in connection with petroleum or gas extraction",
      "Section B · Mining and quarrying / Division 09 · Mining support service activities / Group 091 · Support activities for petroleum and natural gas extraction / Class 0910 · Support activities for petroleum and natural gas extraction / Subclass 09101 · Oil and gas extraction service activities provided on a fee or contract basis:",
  ),
  KeSicActivity(
      "091012",
      "Oil and gas extraction service activities provided on a fee or contract basis:",
      "Section B · Mining and quarrying / Division 09 · Mining support service activities / Group 091 · Support activities for petroleum and natural gas extraction / Class 0910 · Support activities for petroleum and natural gas extraction / Subclass 09101 · Oil and gas extraction service activities provided on a fee or contract basis:",
  ),
  KeSicActivity(
      "091020",
      "Oil and gas field firefighting services",
      "Section B · Mining and quarrying / Division 09 · Mining support service activities / Group 091 · Support activities for petroleum and natural gas extraction / Class 0910 · Support activities for petroleum and natural gas extraction / Subclass 09102 · Oil and gas field firefighting services",
  ),
  KeSicActivity(
      "099001",
      "Exploration services other than for oil and gas and making geological observations at prospective sites",
      "Section B · Mining and quarrying / Division 09 · Mining support service activities / Class 0990 · Support activities for other mining and quarrying / Subclass 09900 · Support activities for other mining and quarrying",
  ),
  KeSicActivity(
      "099009",
      "Other Support activities for other mining and quarrying",
      "Section B · Mining and quarrying / Division 09 · Mining support service activities / Class 0990 · Support activities for other mining and quarrying / Subclass 09900 · Support activities for other mining and quarrying",
  ),
  KeSicActivity(
      "101010",
      "Processing and preserving of beef and related products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10101 · Processing and preserving of beef and related products",
  ),
  KeSicActivity(
      "101020",
      "Processing and preserving of mutton, lamb and related products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10102 · Processing and preserving of mutton, lamb and related products",
  ),
  KeSicActivity(
      "101030",
      "Processing and preserving of pork and related products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10103 · Processing and preserving of pork and related products",
  ),
  KeSicActivity(
      "101040",
      "Processing and preserving of chicken and related products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10104 · Processing and preserving of chicken and related products",
  ),
  KeSicActivity(
      "101050",
      "Processing and preserving of donkey and related products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10105 · Processing and preserving of donkey and related products",
  ),
  KeSicActivity(
      "101060",
      "Processing and preserving of camel and related products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10106 · Processing and preserving of camel and related products",
  ),
  KeSicActivity(
      "101070",
      "Production of hides and skins originating from slaughterhouses, including fellmongery",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10107 · Production of hides and skins originating from slaughterhouses, including fellmongery",
  ),
  KeSicActivity(
      "101080",
      "Processing of animal offal",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10108 · Processing of animal offal",
  ),
  KeSicActivity(
      "101090",
      "Other processing and preservation of other animal meat products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 101 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1010 · Processing and preserving of meat / Subclass 10109 · Other processing and preservation of other animal meat products",
  ),
  KeSicActivity(
      "102011",
      "Preparation and preserving of fish",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 102 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1020 · Processing and preserving of fish, crustaceans and molluscs / Subclass 10201 · Preparation and preservation of fish, crustaceans and molluscs: freezing, deep- freezing, drying, smoking, salting, immersing in brine, canning etc",
  ),
  KeSicActivity(
      "102012",
      "Preparation and preserving of crustaceans and molluscs",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 102 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1020 · Processing and preserving of fish, crustaceans and molluscs / Subclass 10201 · Preparation and preservation of fish, crustaceans and molluscs: freezing, deep- freezing, drying, smoking, salting, immersing in brine, canning etc",
  ),
  KeSicActivity(
      "102021",
      "Production of fish products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 102 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1020 · Processing and preserving of fish, crustaceans and molluscs / Subclass 10202 · Production of fish, crustacean and mollusc products: cooked fish, fish fillets, roes, caviar, caviar substitutes etc",
  ),
  KeSicActivity(
      "102022",
      "Production of crustaceans and molluscs products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 102 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1020 · Processing and preserving of fish, crustaceans and molluscs / Subclass 10202 · Production of fish, crustacean and mollusc products: cooked fish, fish fillets, roes, caviar, caviar substitutes etc",
  ),
  KeSicActivity(
      "102031",
      "Production of fishmeal for human consumption",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 102 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1020 · Processing and preserving of fish, crustaceans and molluscs / Subclass 10203 · Production of fishmeal for human consumption or animal feed",
  ),
  KeSicActivity(
      "102032",
      "Production of fishmeal for animal feed",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 102 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1020 · Processing and preserving of fish, crustaceans and molluscs / Subclass 10203 · Production of fishmeal for human consumption or animal feed",
  ),
  KeSicActivity(
      "102090",
      "Other processing and preserving of fish, crustaceans and molluscs n.e.c",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 102 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1020 · Processing and preserving of fish, crustaceans and molluscs / Subclass 10209 · Other processing and preserving of fish, crustaceans and molluscs",
  ),
  KeSicActivity(
      "103011",
      "Processing and preservation of fruit food products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 103 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1030 · Processing and preserving of fruit and vegetables / Subclass 10301 · Processing and preservation of fruit food products and juices including concentrates",
  ),
  KeSicActivity(
      "103012",
      "Processing of fruit juices including concentrates",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 103 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1030 · Processing and preserving of fruit and vegetables / Subclass 10301 · Processing and preservation of fruit food products and juices including concentrates",
  ),
  KeSicActivity(
      "103021",
      "Processing and preservation of vegetable food products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 103 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1030 · Processing and preserving of fruit and vegetables / Subclass 10302 · Processing and preserving of vegetables food products and juices including concentrates",
  ),
  KeSicActivity(
      "103022",
      "Processing of vegetable juices including concentrates",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 103 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1030 · Processing and preserving of fruit and vegetables / Subclass 10302 · Processing and preserving of vegetables food products and juices including concentrates",
  ),
  KeSicActivity(
      "103030",
      "Processing and preserving of potatoes including other tubers and bananas",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 103 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1030 · Processing and preserving of fruit and vegetables / Subclass 10303 · Processing and preserving of potatoes including other tubers and bananas",
  ),
  KeSicActivity(
      "103040",
      "Processing of nut foods",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 103 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1030 · Processing and preserving of fruit and vegetables / Subclass 10304 · Processing of nut foods",
  ),
  KeSicActivity(
      "103050",
      "Manufacture of jams, marmalades, table jellies and pastes",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 103 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1030 · Processing and preserving of fruit and vegetables / Subclass 10305 · Manufacture of jams, marmalades, table jellies and pastes",
  ),
  KeSicActivity(
      "103090",
      "Other processing and preserving of fruit and vegetables",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 103 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1030 · Processing and preserving of fruit and vegetables / Subclass 10309 · Other processing and preserving of fruit and vegetables",
  ),
  KeSicActivity(
      "104001",
      "Manufacture of vegetable oils and fats excluding corn oil",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 104 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1040 · Manufacture of vegetable and animal oils and fats / Subclass 10400 · Manufacture of vegetable and animal oils and fats",
  ),
  KeSicActivity(
      "104009",
      "Manufacture of other vegetable and animal oils and fats n.e.c",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 104 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1040 · Manufacture of vegetable and animal oils and fats / Subclass 10400 · Manufacture of vegetable and animal oils and fats",
  ),
  KeSicActivity(
      "105011",
      "Manufacture of fresh liquid milk, pasteurized, sterilized, homogenized and/or ultra-heat treated",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 105 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1050 · Manufacture of dairy products / Subclass 10501 · Manufacture of fresh liquid milk products, milk-based drinks and dried or concentrated milk",
  ),
  KeSicActivity(
      "105012",
      "Manufacture of milk-based drinks",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 105 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1050 · Manufacture of dairy products / Subclass 10501 · Manufacture of fresh liquid milk products, milk-based drinks and dried or concentrated milk",
  ),
  KeSicActivity(
      "105013",
      "Manufacture of dried or concentrated milk whether or not sweetened",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 105 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1050 · Manufacture of dairy products / Subclass 10501 · Manufacture of fresh liquid milk products, milk-based drinks and dried or concentrated milk",
  ),
  KeSicActivity(
      "105091",
      "Manufacture of yoghurt",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 105 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1050 · Manufacture of dairy products / Subclass 10509 · Manufacture of other dairy products n.e.c",
  ),
  KeSicActivity(
      "105092",
      "Manufacture of fermented milk e.g. mala",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 105 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1050 · Manufacture of dairy products / Subclass 10509 · Manufacture of other dairy products n.e.c",
  ),
  KeSicActivity(
      "105093",
      "Manufacture of butter, ghee and cheese",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 105 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1050 · Manufacture of dairy products / Subclass 10509 · Manufacture of other dairy products n.e.c",
  ),
  KeSicActivity(
      "105094",
      "Manufacture of ice cream and other edible ice such as sorbet(non-dairy ice cream)",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 105 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1050 · Manufacture of dairy products / Subclass 10509 · Manufacture of other dairy products n.e.c",
  ),
  KeSicActivity(
      "105099",
      "Manufacture of other dairy products n.e.c",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 105 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1050 · Manufacture of dairy products / Subclass 10509 · Manufacture of other dairy products n.e.c",
  ),
  KeSicActivity(
      "106111",
      "Maize milling",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1061 · Manufacture of grain mill products / Subclass 10611 · Grain milling",
  ),
  KeSicActivity(
      "106112",
      "Wheat milling",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1061 · Manufacture of grain mill products / Subclass 10611 · Grain milling",
  ),
  KeSicActivity(
      "106113",
      "Rice milling",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1061 · Manufacture of grain mill products / Subclass 10611 · Grain milling",
  ),
  KeSicActivity(
      "106119",
      "Other grain milling n.e.c",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1061 · Manufacture of grain mill products / Subclass 10611 · Grain milling",
  ),
  KeSicActivity(
      "106120",
      "Vegetable milling: production of flour or meal of dried leguminous vegetables, of roots or tubers, or of edible nuts",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1061 · Manufacture of grain mill products / Subclass 10612 · Vegetable milling: production of flour or meal of dried leguminous vegetables, of roots or tubers, or of edible nuts",
  ),
  KeSicActivity(
      "106130",
      "Manufacture of cereal breakfast foods",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1061 · Manufacture of grain mill products / Subclass 10613 · Manufacture of cereal breakfast foods",
  ),
  KeSicActivity(
      "106190",
      "Manufacture of other grain mill products n.e.c",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1061 · Manufacture of grain mill products / Subclass 10619 · Manufacture of other grain mill products n.e.c",
  ),
  KeSicActivity(
      "106210",
      "Manufacture of glucose, glucose syrup, maltose, inulin etc",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1062 · Manufacture of starches and starch products / Subclass 10621 · Manufacture of glucose, glucose syrup, maltose, inulin etc",
  ),
  KeSicActivity(
      "106230",
      "Manufacture of corn oil",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1062 · Manufacture of starches and starch products / Subclass 10623 · Manufacture of corn oil",
  ),
  KeSicActivity(
      "106290",
      "Manufacture of other starches and starch products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 106 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1062 · Manufacture of starches and starch products / Subclass 10629 · Manufacture of other starches and starch products",
  ),
  KeSicActivity(
      "107110",
      "Manufacture of bread and rolls",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1071 · Manufacture of bakery products / Subclass 10711 · Manufacture of bread and rolls",
  ),
  KeSicActivity(
      "107120",
      "Manufacture of fresh pastry, cakes, pies, tarts etc",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1071 · Manufacture of bakery products / Subclass 10712 · Manufacture of fresh pastry, cakes, pies, tarts etc",
  ),
  KeSicActivity(
      "107131",
      "Manufacture of biscuits",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1071 · Manufacture of bakery products / Subclass 10713 · Manufacture of rusks, snack products(cookies, crackers etc), biscuits and other “dry” bakery products",
  ),
  KeSicActivity(
      "107139",
      "Other manufacture of rusks, snack products(cookies, crackers etc), and other “dry” bakery products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1071 · Manufacture of bakery products / Subclass 10713 · Manufacture of rusks, snack products(cookies, crackers etc), biscuits and other “dry” bakery products",
  ),
  KeSicActivity(
      "107190",
      "Manufacture of other bakery products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1071 · Manufacture of bakery products / Subclass 10719 · Manufacture of other bakery products",
  ),
  KeSicActivity(
      "107210",
      "Manufacture or refining of sugar (sucrose) and sugar substitutes from the juice of cane",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1072 · Manufacture of sugar / Subclass 10721 · Manufacture or refining of sugar (sucrose) and sugar substitutes from the juice of cane",
  ),
  KeSicActivity(
      "107220",
      "Manufacture of molasses",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1072 · Manufacture of sugar / Subclass 10722 · Manufacture of molasses",
  ),
  KeSicActivity(
      "107290",
      "Manufacture of other sugar n.e.c e.g. jaggery",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1072 · Manufacture of sugar / Subclass 10729 · Manufacture of other sugar n.e.c e.g. jaggery",
  ),
  KeSicActivity(
      "107311",
      "Manufacture of chocolate and chocolate confectionery",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1073 · Manufacture of cocoa, chocolate and sugar confectionery / Subclass 10731 · Manufacture of chocolate and chocolate confectionery, cocoa and cocoa products",
  ),
  KeSicActivity(
      "107312",
      "Manufacture of cocoa products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1073 · Manufacture of cocoa, chocolate and sugar confectionery / Subclass 10731 · Manufacture of chocolate and chocolate confectionery, cocoa and cocoa products",
  ),
  KeSicActivity(
      "107320",
      "Manufacture of sugar confectionery: caramels, cachous, nougats, fondant, white chocolate",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1073 · Manufacture of cocoa, chocolate and sugar confectionery / Subclass 10732 · Manufacture of sugar confectionery: caramels, cachous, nougats, fondant, white chocolate",
  ),
  KeSicActivity(
      "107330",
      "Manufacture of chewing gum, confectionery lozenges and pastilles",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1073 · Manufacture of cocoa, chocolate and sugar confectionery / Subclass 10733 · Manufacture of chewing gum, confectionery lozenges and pastilles",
  ),
  KeSicActivity(
      "107390",
      "Manufacture of other cocoa, chocolate and sugar confectionery",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1073 · Manufacture of cocoa, chocolate and sugar confectionery / Subclass 10739 · Manufacture of other cocoa, chocolate and sugar confectionery",
  ),
  KeSicActivity(
      "107410",
      "Manufacture of pastas such as spaghetti, macaroni and noodles, whether or not cooked or stuffed",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1074 · Manufacture of macaroni, noodles, couscous and similar farinaceous products / Subclass 10741 · Manufacture of pastas such as spaghetti, macaroni and noodles, whether or not cooked or stuffed",
  ),
  KeSicActivity(
      "107490",
      "Manufacture of other macaroni, noodles, couscous and similar farinaceous products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1074 · Manufacture of macaroni, noodles, couscous and similar farinaceous products / Subclass 10749 · Manufacture of other macaroni, noodles, couscous and similar farinaceous products",
  ),
  KeSicActivity(
      "107500",
      "Manufacture of prepared meals and dishes",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1075 · Manufacture of prepared meals and dishes / Subclass 10750 · Manufacture of prepared meals and dishes",
  ),
  KeSicActivity(
      "107601",
      "Coffee curing including pulping",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1076 · Processing of coffee / Subclass 10760 · Coffee curing, roasting, grinding blending etc. and manufacturing of coffee products",
  ),
  KeSicActivity(
      "107602",
      "Roasting, grinding and blending of coffee",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1076 · Processing of coffee / Subclass 10760 · Coffee curing, roasting, grinding blending etc. and manufacturing of coffee products",
  ),
  KeSicActivity(
      "107609",
      "Manufacturing of other coffee products",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1076 · Processing of coffee / Subclass 10760 · Coffee curing, roasting, grinding blending etc. and manufacturing of coffee products",
  ),
  KeSicActivity(
      "107700",
      "Processing and blending of tea including manufacture of instant tea",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1077 · Processing of tea / Subclass 10770 · Processing and blending of tea including manufacture of instant tea",
  ),
  KeSicActivity(
      "107810",
      "Processing of salt into food-grade salt, e.g. iodized salt",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1078 · Manufacture of special foods, spices, sauces, condiments and processing of salt into food-grade salt / Subclass 10781 · Processing of salt into food-grade salt, e.g. iodized salt",
  ),
  KeSicActivity(
      "107820",
      "Manufacture of special foods, such as: infant formula, baby foods, etc",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1078 · Manufacture of special foods, spices, sauces, condiments and processing of salt into food-grade salt / Subclass 10782 · Manufacture of special foods, such as: infant formula, baby foods, etc",
  ),
  KeSicActivity(
      "107830",
      "Manufacture of spices, sauces and condiments",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1078 · Manufacture of special foods, spices, sauces, condiments and processing of salt into food-grade salt / Subclass 10783 · Manufacture of spices, sauces and condiments",
  ),
  KeSicActivity(
      "107910",
      "Processing of soya products n.e.c e.g. soya meat",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1079 · Manufacture of other food products n.e.c",
  ),
  KeSicActivity(
      "107990",
      "Manufacture of other food products n.e.c",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 107 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1079 · Manufacture of other food products n.e.c / Subclass 10799 · Manufacture of other food products n.e.c",
  ),
  KeSicActivity(
      "108011",
      "Manufacture of prepared feeds for pets, including dogs, cats, birds, fish etc",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 108 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1080 · Manufacture of prepared animal feeds / Subclass 10801 · Manufacture of prepared feeds for animals and pets excluding unmixed feeds",
  ),
  KeSicActivity(
      "108012",
      "Manufacture of prepared feeds for farm animals, including animal feed concentrates and feed supplements",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 108 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1080 · Manufacture of prepared animal feeds / Subclass 10801 · Manufacture of prepared feeds for animals and pets excluding unmixed feeds",
  ),
  KeSicActivity(
      "108091",
      "Preparation of unmixed (single) feeds for farm animals",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 108 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1080 · Manufacture of prepared animal feeds / Subclass 10809 · Manufacture of other prepared animal feeds",
  ),
  KeSicActivity(
      "108092",
      "Treatment of slaughter waste to produce animal feeds",
      "Section C · Manufacturing / Division 10 · Manufacture of food products / Group 108 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1080 · Manufacture of prepared animal feeds / Subclass 10809 · Manufacture of other prepared animal feeds",
  ),
  KeSicActivity(
      "110110",
      "Manufacture of spirit for production of whisky, brandy, gin, liqueurs",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1101 · Distilling, rectifying and blending of spirits / Subclass 11011 · Manufacture of spirit for production of whisky, brandy, gin, liqueurs",
  ),
  KeSicActivity(
      "110120",
      "Manufacture of distilled, potable, alcoholic beverages: whisky, brandy, gin, liqueurs, excluding traditional liqueurs “mixed drinks” etc",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1101 · Distilling, rectifying and blending of spirits / Subclass 11012 · Manufacture of distilled, potable, alcoholic beverages: whisky, brandy, gin, liqueurs, excluding traditional liqueurs “mixed drinks” etc",
  ),
  KeSicActivity(
      "110190",
      "Other distilling, rectifying and blending of spirits n.e.c excluding white spirits",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1101 · Distilling, rectifying and blending of spirits / Subclass 11019 · Other distilling, rectifying and blending of spirits n.e.c excluding white spirits",
  ),
  KeSicActivity(
      "110200",
      "Manufacture of wines",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1102 · Manufacture of wines / Subclass 11020 · Manufacture of wines",
  ),
  KeSicActivity(
      "110310",
      "Manufacture of malt",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1103 · Manufacture of malt liquors and malt / Subclass 11031 · Manufacture of malt",
  ),
  KeSicActivity(
      "110320",
      "Manufacture of malt liquors, such as beer, ale, porter and stout",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1103 · Manufacture of malt liquors and malt / Subclass 11032 · Manufacture of malt liquors, such as beer, ale, porter and stout",
  ),
  KeSicActivity(
      "110390",
      "Other manufacture of malt liquors and malt n.e.c",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1103 · Manufacture of malt liquors and malt / Subclass 11039 · Other manufacture of malt liquors and malt n.e.c",
  ),
  KeSicActivity(
      "110410",
      "Manufactureofsodasincludingtonicwater",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1104 · Manufacture of soft drinks; production of mineral waters and other bottled waters / Subclass 11041 · Manufactureofsodasincludingtonicwater",
  ),
  KeSicActivity(
      "110420",
      "Production of natural mineral waters and other bottled waters",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1104 · Manufacture of soft drinks; production of mineral waters and other bottled waters / Subclass 11042 · Production of natural mineral waters and other bottled waters",
  ),
  KeSicActivity(
      "110430",
      "Manufacture of non-alcoholic flavoured and/or sweetened waters: lemonade, orangeade, fruit drinks ,squashes e.g. treetop, quencher etc",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1104 · Manufacture of soft drinks; production of mineral waters and other bottled waters / Subclass 11043 · Manufacture of non-alcoholic flavoured and/or sweetened waters: lemonade, orangeade, fruit drinks ,squashes e.g. treetop, quencher etc",
  ),
  KeSicActivity(
      "110440",
      "Manufacture of non-alcoholic beverages such as energy drinks, except non- alcoholic beer and wine",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1104 · Manufacture of soft drinks; production of mineral waters and other bottled waters / Subclass 11044 · Manufacture of non-alcoholic beverages such as energy drinks, except non- alcoholic beer and wine",
  ),
  KeSicActivity(
      "110490",
      "Other manufacture of soft drinks; production of mineral waters and other bottled waters",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1104 · Manufacture of soft drinks; production of mineral waters and other bottled waters / Subclass 11049 · Other manufacture of soft drinks; production of mineral waters and other bottled waters",
  ),
  KeSicActivity(
      "110910",
      "Manufacture of traditional alcoholic beverages e.g. muratina, busaa, mnazi etc",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1109 · Other manufacture of beverages / Subclass 11091 · Manufacture of traditional alcoholic beverages e.g. muratina, busaa, mnazi etc",
  ),
  KeSicActivity(
      "110990",
      "Other manufacture of beverages n.e.c",
      "Section C · Manufacturing / Division 11 · Manufacture of beverages / Group 110 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1109 · Other manufacture of beverages / Subclass 11099 · Other manufacture of beverages n.e.c",
  ),
  KeSicActivity(
      "120010",
      "Manufacture of tobacco products and products of tobacco substitutes except snuff: cigarettes, cigarette tobacco, cigars, pipe tobacco, chewing tobacco",
      "Section C · Manufacturing / Division 12 · Manufacture of tobacco products / Group 120 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1200 · Manufacture of tobacco products / Subclass 12001 · Manufacture of tobacco products and products of tobacco substitutes except snuff: cigarettes, cigarette",
  ),
  KeSicActivity(
      "120020",
      "Manufacture of snuff",
      "Section C · Manufacturing / Division 12 · Manufacture of tobacco products / Group 120 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1200 · Manufacture of tobacco products / Subclass 12002 · Manufacture of snuff",
  ),
  KeSicActivity(
      "120090",
      "Other manufacture of tobacco products",
      "Section C · Manufacturing / Division 12 · Manufacture of tobacco products / Group 120 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1200 · Manufacture of tobacco products / Subclass 12009 · Other manufacture of tobacco products",
  ),
  KeSicActivity(
      "131100",
      "Preparation and spinning of textile fibres",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 131 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1311 · Preparation and spinning of textile fibres / Subclass 13110 · Preparation and spinning of textile fibres",
  ),
  KeSicActivity(
      "131200",
      "Weaving of textiles",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 131 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1312 · Weaving of textiles / Subclass 13120 · Weaving of textiles",
  ),
  KeSicActivity(
      "131300",
      "Finishing of textiles",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 131 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1313 · Finishing of textiles / Subclass 13130 · Finishing of textiles",
  ),
  KeSicActivity(
      "139100",
      "Manufacture of knitted and crocheted fabrics",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1391 · Manufacture of knitted and crocheted fabrics / Subclass 13910 · Manufacture of knitted and crocheted fabrics",
  ),
  KeSicActivity(
      "139210",
      "Manufacture, of made-up articles of any textile material, including of knitted or crocheted fabrics: blankets, pillows",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1392 · Manufacture of made-up textile articles, except apparel / Subclass 13921 · Manufacture, of made-up articles of any textile material, including of knitted or",
  ),
  KeSicActivity(
      "139221",
      "Manufacture of tarpaulins and tents",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1392 · Manufacture of made-up textile articles, except apparel / Subclass 13922 · Manufacture of tarpaulins, tents, camping goods, sails, sun blinds, loose covers for cars, machines or furniture etc",
  ),
  KeSicActivity(
      "139229",
      "Manufacture of camping goods, sails, sun blinds, loose covers for cars, machines or furniture etc",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1392 · Manufacture of made-up textile articles, except apparel / Subclass 13922 · Manufacture of tarpaulins, tents, camping goods, sails, sun blinds, loose covers for cars, machines or furniture etc",
  ),
  KeSicActivity(
      "139290",
      "Manufacture of other made-up textile articles, except apparel",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1392 · Manufacture of made-up textile articles, except apparel / Subclass 13929 · Manufacture of other made-up textile articles, except apparel",
  ),
  KeSicActivity(
      "139300",
      "Manufacture of carpets and rugs",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1393 · Manufacture of carpets and rugs / Subclass 13930 · Manufacture of carpets and rugs",
  ),
  KeSicActivity(
      "139410",
      "Manufacture of cordage, rope, twine and netting from synthetic fibre",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1394 · Manufacture of cordage, rope, twine and netting / Subclass 13941 · Manufacture of cordage, rope, twine and netting from synthetic fibre",
  ),
  KeSicActivity(
      "139420",
      "Manufacture of cordage, rope, twine and netting from natural fibre",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1394 · Manufacture of cordage, rope, twine and netting / Subclass 13942 · Manufacture of cordage, rope, twine and netting from natural fibre",
  ),
  KeSicActivity(
      "139910",
      "Manufacture of labels, badges etc",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1399 · Manufacture of other textiles n.e.c / Subclass 13991 · Manufacture of labels, badges etc",
  ),
  KeSicActivity(
      "139920",
      "Manufacture of tulles and other net fabrics, and of lace and embroidery, in the piece, in strips or in motifs",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1399 · Manufacture of other textiles n.e.c / Subclass 13992 · Manufacture of tulles and other net fabrics, and of lace and embroidery, in the piece, in strips or in motifs",
  ),
  KeSicActivity(
      "139990",
      "Manufacture of other textiles n.e.c",
      "Section C · Manufacturing / Division 13 · Manufacture of textiles / Group 139 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1399 · Manufacture of other textiles n.e.c / Subclass 13999 · Manufacture of other textiles n.e.c",
  ),
  KeSicActivity(
      "141000",
      "Manufacture of wearing apparel, except fur apparel",
      "Section C · Manufacturing / Division 14 · Manufacture of wearing apparel / Group 141 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1410 · Manufacture of wearing apparel, except fur apparel / Subclass 14100 · Manufacture of wearing apparel, except fur apparel",
  ),
  KeSicActivity(
      "142000",
      "Manufacture of articles of fur",
      "Section C · Manufacturing / Division 14 · Manufacture of wearing apparel / Group 142 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1420 · Manufacture of articles of fur / Subclass 14200 · Manufacture of articles of fur",
  ),
  KeSicActivity(
      "143000",
      "Manufacture of knitted and crocheted apparel",
      "Section C · Manufacturing / Division 14 · Manufacture of wearing apparel / Group 143 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1430 · Manufacture of knitted and crocheted apparel / Subclass 14300 · Manufacture of knitted and crocheted apparel",
  ),
  KeSicActivity(
      "151100",
      "Tanning and dressing of leather; dressing and dyeing of fur",
      "Section C · Manufacturing / Division 15 · Manufacture of leather and related products / Group 151 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1511 · Tanning and dressing of leather; dressing and dyeing of fur / Subclass 15110 · Tanning and dressing of leather; dressing and dyeing of fur",
  ),
  KeSicActivity(
      "151200",
      "Manufacture of luggage, handbags and the like, saddlery and harness",
      "Section C · Manufacturing / Division 15 · Manufacture of leather and related products / Group 151 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1512 · Manufacture of luggage, handbags and the like, saddlery and harness / Subclass 15120 · Manufacture of luggage, handbags and the like, saddlery and harness",
  ),
  KeSicActivity(
      "152000",
      "Manufacture of footwear except plastic footwear parts",
      "Section C · Manufacturing / Division 15 · Manufacture of leather and related products / Group 152 · Division IS SIC Group Code KeS SIC Class Code KeS SIC Code KeS SIC Codes / Class 1520 · Manufacture of footwear / Subclass 15200 · Manufacture of footwear except plastic footwear parts",
  ),
  KeSicActivity(
      "161010",
      "Sawing, planning and machining of wood ,slicing, peeling or chipping logs",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 161 · Sawmilling and planning of wood / Class 1610 · Sawmilling and planning of wood / Subclass 16101 · Sawing, planning and machining of wood ,slicing, peeling or chipping logs",
  ),
  KeSicActivity(
      "161020",
      "Impregnation or chemical treatment of wood with preservatives or other materials",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 161 · Sawmilling and planning of wood / Class 1610 · Sawmilling and planning of wood / Subclass 16102 · Impregnation or chemical treatment of wood with preservatives or other materials",
  ),
  KeSicActivity(
      "161090",
      "Other sawmilling and planning of wood",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 161 · Sawmilling and planning of wood / Class 1610 · Sawmilling and planning of wood / Subclass 16109 · Other sawmilling and planning of wood",
  ),
  KeSicActivity(
      "162101",
      "Manufacture of veneer sheets thin enough to be used for veneering, making plywood or other purposes:",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1621 · Manufacture of veneer sheets and wood- based panels / Subclass 16210 · Manufacture of veneer sheets and wood- based panels",
  ),
  KeSicActivity(
      "162102",
      "Manufacture of plywood, veneer panels and similar laminated wood boards and sheets",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1621 · Manufacture of veneer sheets and wood- based panels / Subclass 16210 · Manufacture of veneer sheets and wood- based panels",
  ),
  KeSicActivity(
      "162109",
      "Other manufacture of veneer sheets and wood-based panels",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1621 · Manufacture of veneer sheets and wood- based panels / Subclass 16210 · Manufacture of veneer sheets and wood- based panels",
  ),
  KeSicActivity(
      "162210",
      "Manufacture of wooden goods intended to be used primarily in the construction industry",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1622 · Manufacture of builders’ carpentry and joinery / Subclass 16221 · Manufacture of wooden goods intended to be used primarily in the construction industry",
  ),
  KeSicActivity(
      "162220",
      "Manufacture of prefabricated buildings, or elements thereof, predominantly of wood",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1622 · Manufacture of builders’ carpentry and joinery / Subclass 16222 · Manufacture of prefabricated buildings, or elements thereof, predominantly of wood",
  ),
  KeSicActivity(
      "162290",
      "Other Manufacture of builders’ carpentry and joinery",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1622 · Manufacture of builders’ carpentry and joinery / Subclass 16229 · Other Manufacture of builders’ carpentry and joinery",
  ),
  KeSicActivity(
      "162300",
      "Manufacture of wooden containers",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1623 · Manufacture of wooden containers / Subclass 16230 · Manufacture of wooden containers",
  ),
  KeSicActivity(
      "162910",
      "Weaving of basket, makuti, pakacha, mat etc",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1629 · Manufacture of other products of wood; manufacture of articles of cork, straw and plaiting materials / Subclass 16291 · Weaving of basket, makuti, pakacha, mat etc",
  ),
  KeSicActivity(
      "162920",
      "Manufacture of wooden mirror and picture frames,woodenframesforartists’canvases, wooden clothes hangers etc, including wood carvings",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1629 · Manufacture of other products of wood; manufacture of articles of cork, straw and plaiting materials / Subclass 16292 · Manufacture of wooden mirror and picture frames,woodenframesforartists’canvases, wooden clothes hangers etc, including wood carvings",
  ),
  KeSicActivity(
      "162990",
      "Manufacture of other products of wood; manufacture of articles of cork, straw and plaiting materials n.e.c",
      "Section C · Manufacturing / Division 16 · Manufacture of wood and of products of wood and cork, except furniture; manufacture of articles of straw and plaiting materials / Group 162 · Manufacture of products of wood, cork, straw and plaiting materials / Class 1629 · Manufacture of other products of wood; manufacture of articles of cork, straw and plaiting materials / Subclass 16299 · Manufacture of other products of wood; manufacture of articles of cork, straw and plaiting materials n.e.c",
  ),
  KeSicActivity(
      "170110",
      "Manufactureofbleached,semi-bleachedor unbleached paper pulp by mechanical, chemical (dissolving or non-dissolving) or semi-chemical processes",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1701 · Manufactureofpulp,paperandpaperboard / Subclass 17011 · Manufactureofbleached,semi-bleachedor unbleached paper pulp by mechanical, chemical (dissolving or non-dissolving) or semi-chemical processes",
  ),
  KeSicActivity(
      "170121",
      "Manufacture of paper and paperboard intended for further industrial processing",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1701 · Manufactureofpulp,paperandpaperboard / Subclass 17012 · Manufacture of paper and paperboard intended for further industrial processing and/ormanufactureofnewsprintandother printing or writing paper",
  ),
  KeSicActivity(
      "170122",
      "Manufacture of newsprint and other printing or writing paper",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1701 · Manufactureofpulp,paperandpaperboard / Subclass 17012 · Manufacture of paper and paperboard intended for further industrial processing and/ormanufactureofnewsprintandother printing or writing paper",
  ),
  KeSicActivity(
      "170130",
      "Removal of ink and manufacture of pulp from waste paper",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1701 · Manufactureofpulp,paperandpaperboard / Subclass 17013 · Removal of ink and manufacture of pulp from waste paper",
  ),
  KeSicActivity(
      "170140",
      "Manufacture of handmade paper",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1701 · Manufactureofpulp,paperandpaperboard / Subclass 17014 · Manufacture of handmade paper",
  ),
  KeSicActivity(
      "170190",
      "Other manufacture of pulp, paper and paperboard",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1701 · Manufactureofpulp,paperandpaperboard / Subclass 17019 · Other manufacture of pulp, paper and paperboard",
  ),
  KeSicActivity(
      "170201",
      "Manufacture of containers of corrugated paper, paperboard and solid board",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1702 · Manufacture of corrugated paper and paperboard and of containers of paper and paperboard / Subclass 17020 · Manufacture of corrugated paper and paperboard and of containers of paper and paperboard",
  ),
  KeSicActivity(
      "170202",
      "Manufacture of corrugated paper, paperboard and solid board",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1702 · Manufacture of corrugated paper and paperboard and of containers of paper and paperboard / Subclass 17020 · Manufacture of corrugated paper and paperboard and of containers of paper and paperboard",
  ),
  KeSicActivity(
      "170203",
      "Manufacture of sacks and bags of paper",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1702 · Manufacture of corrugated paper and paperboard and of containers of paper and paperboard / Subclass 17020 · Manufacture of corrugated paper and paperboard and of containers of paper and paperboard",
  ),
  KeSicActivity(
      "170209",
      "Other manufacture of corrugated paper and paperboard and of containers of paper and paperboard n.e.c",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1702 · Manufacture of corrugated paper and paperboard and of containers of paper and paperboard / Subclass 17020 · Manufacture of corrugated paper and paperboard and of containers of paper and paperboard",
  ),
  KeSicActivity(
      "170911",
      "Manufacture of household and personal hygiene paper and cellulose wadding products",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1709 · Manufacture of other articles of paper and paperboard / Subclass 17091 · Manufacture of household and personal hygiene products from paper and paperboard",
  ),
  KeSicActivity(
      "170912",
      "Manufacture of household and personal hygiene paper and cellulose wadding products",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1709 · Manufacture of other articles of paper and paperboard / Subclass 17091 · Manufacture of household and personal hygiene products from paper and paperboard",
  ),
  KeSicActivity(
      "170913",
      "Manufacture of textile wadding and articles of wadding: sanitary towels, tampons etc",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1709 · Manufacture of other articles of paper and paperboard / Subclass 17091 · Manufacture of household and personal hygiene products from paper and paperboard",
  ),
  KeSicActivity(
      "170921",
      "Manufacture of printing , writing and photocopying papers",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1709 · Manufacture of other articles of paper and paperboard / Subclass 17092 · Manufacture of stationery from paper and paperboard",
  ),
  KeSicActivity(
      "170922",
      "Manufactureofboxes,pouches,walletsand writing compendiums containing an assortment of paper stationery, envelopes and letter-cards, labels,",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1709 · Manufacture of other articles of paper and paperboard / Subclass 17092 · Manufacture of stationery from paper and paperboard",
  ),
  KeSicActivity(
      "170923",
      "Manufacture of exercise books, registers, accounting books, binders, albums and similar educational and commercial stationery",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1709 · Manufacture of other articles of paper and paperboard / Subclass 17092 · Manufacture of stationery from paper and paperboard",
  ),
  KeSicActivity(
      "170990",
      "Manufacture of other articles of paper and paperboard n.e.c",
      "Section C · Manufacturing / Division 17 · Manufacture of paper and paper products / Group 170 · Manufacture of paper and paper products / Class 1709 · Manufacture of other articles of paper and paperboard / Subclass 17099 · Manufacture of other articles of paper and paperboard n.e.c",
  ),
  KeSicActivity(
      "181110",
      "Printing of newspapers, magazines and other periodicals, books and brochures, maps, atlases, posters etc",
      "Section C · Manufacturing / Division 18 · Printing and reproduction of recorded media / Group 181 · Printing and service activities related to printing / Class 1811 · Printing / Subclass 18111 · Printing of newspapers, magazines and other periodicals, books and brochures, maps, atlases, posters etc",
  ),
  KeSicActivity(
      "181120",
      "Printing directly onto textiles, plastic, glass, metal, wood and ceramics (except silkscreen printing on textiles and wearing apparel)",
      "Section C · Manufacturing / Division 18 · Printing and reproduction of recorded media / Group 181 · Printing and service activities related to printing / Class 1811 · Printing / Subclass 18112 · Printing directly onto textiles, plastic, glass, metal, wood and ceramics (except silkscreen printing on textiles and wearing apparel",
  ),
  KeSicActivity(
      "181130",
      "Printing of bank notes, currency notes",
      "Section C · Manufacturing / Division 18 · Printing and reproduction of recorded media / Group 181 · Printing and service activities related to printing / Class 1811 · Printing / Subclass 18113 · Printing of bank notes, currency notes",
  ),
  KeSicActivity(
      "181190",
      "Other printing n.e.c",
      "Section C · Manufacturing / Division 18 · Printing and reproduction of recorded media / Group 181 · Printing and service activities related to printing / Class 1811 · Printing / Subclass 18119 · Other printing n.e.c",
  ),
  KeSicActivity(
      "181200",
      "Service activities related to printing",
      "Section C · Manufacturing / Division 18 · Printing and reproduction of recorded media / Group 181 · Printing and service activities related to printing / Class 1812 · Service activities related to printing / Subclass 18120 · Service activities related to printing",
  ),
  KeSicActivity(
      "182000",
      "Reproduction of recorded media",
      "Section C · Manufacturing / Division 18 · Printing and reproduction of recorded media / Group 182 · Reproduction of recorded media / Class 1820 · Reproduction of recorded media / Subclass 18200 · Reproduction of recorded media",
  ),
  KeSicActivity(
      "191000",
      "Manufacture of coke oven products",
      "Section C · Manufacturing / Division 19 · Manufacture of coke and refined petroleum products / Group 191 · Manufacture of coke oven products / Class 1910 · Manufacture of coke oven products / Subclass 19100 · Manufacture of coke oven products",
  ),
  KeSicActivity(
      "192010",
      "Production of motor fuel: gasoline, kerosene and light, medium and heavy fuel oil etc",
      "Section C · Manufacturing / Division 19 · Manufacture of coke and refined petroleum products / Group 192 · Manufacture of refined petroleum products / Class 1920 · Manufacture of refined petroleum products / Subclass 19201 · Production of motor fuel: gasoline, kerosene and light, medium and heavy fuel oil etc",
  ),
  KeSicActivity(
      "192020",
      "Manufacture ofoil-based lubricatingoilsor greases, including from waste oil",
      "Section C · Manufacturing / Division 19 · Manufacture of coke and refined petroleum products / Group 192 · Manufacture of refined petroleum products / Class 1920 · Manufacture of refined petroleum products / Subclass 19202 · Manufactureofoil-based lubricatingoilsor greases, including from waste oil",
  ),
  KeSicActivity(
      "192030",
      "Manufacture of various products: white spirit, Vaseline, paraffin wax, petroleum jelly etc",
      "Section C · Manufacturing / Division 19 · Manufacture of coke and refined petroleum products / Group 192 · Manufacture of refined petroleum products / Class 1920 · Manufacture of refined petroleum products / Subclass 19203 · Manufacture of various products: white spirit, Vaseline, paraffin wax, petroleum jelly etc",
  ),
  KeSicActivity(
      "192040",
      "Production of gaseous fuels(LPG)",
      "Section C · Manufacturing / Division 19 · Manufacture of coke and refined petroleum products / Group 192 · Manufacture of refined petroleum products / Class 1920 · Manufacture of refined petroleum products / Subclass 19204 · Production of gaseous fuels(LPG)",
  ),
  KeSicActivity(
      "192050",
      "Manufacture of hard-coal and lignite fuel briquettes",
      "Section C · Manufacturing / Division 19 · Manufacture of coke and refined petroleum products / Group 192 · Manufacture of refined petroleum products / Class 1920 · Manufacture of refined petroleum products / Subclass 19205 · Manufacture of hard-coal and lignite fuel briquettes",
  ),
  KeSicActivity(
      "192090",
      "Other manufacture of refined petroleum products",
      "Section C · Manufacturing / Division 19 · Manufacture of coke and refined petroleum products / Group 192 · Manufacture of refined petroleum products / Class 1920 · Manufacture of refined petroleum products / Subclass 19209 · Other manufacture of refined petroleum products",
  ),
  KeSicActivity(
      "201110",
      "Manufacture of liquefied or compressed inorganic industrial or medical gases",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2011 · Manufacture of basic chemicals / Subclass 20111 · Manufacture of liquefied or compressed inorganic industrial or medical gases",
  ),
  KeSicActivity(
      "201120",
      "Manufacture of dyes and pigments from any source in basic form or as concentrate",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2011 · Manufacture of basic chemicals / Subclass 20112 · Manufacture of dyes and pigments from any source in basic form or as concentrate",
  ),
  KeSicActivity(
      "201130",
      "Manufacture of inorganic acids except nitricacid,alkalis,lyesandotherinorganic bases except ammonia",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2011 · Manufacture of basic chemicals / Subclass 20113 · Manufacture of inorganic acids except nitricacid,alkalis,lyesandotherinorganic bases except ammonia",
  ),
  KeSicActivity(
      "201140",
      "Manufacture of basic organic chemicals",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2011 · Manufacture of basic chemicals / Subclass 20114 · Manufacture of basic organic chemicals",
  ),
  KeSicActivity(
      "201150",
      "Manufacture of distilled water",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2011 · Manufacture of basic chemicals / Subclass 20115 · Manufacture of distilled water",
  ),
  KeSicActivity(
      "201190",
      "Manufacture of other basic chemicals",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2011 · Manufacture of basic chemicals / Subclass 20119 · Manufacture of other basic chemicals",
  ),
  KeSicActivity(
      "201210",
      "Manufacture of fertilizers",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2012 · Manufacture of fertilizers and nitrogen compounds / Subclass 20121 · Manufacture of fertilizers",
  ),
  KeSicActivity(
      "201220",
      "Manufacture of associated nitrogen products",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2012 · Manufacture of fertilizers and nitrogen compounds / Subclass 20122 · Manufacture of associated nitrogen products",
  ),
  KeSicActivity(
      "201290",
      "Manufacture of other fertilizers and nitrogen compounds n.e.c",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2012 · Manufacture of fertilizers and nitrogen compounds / Subclass 20129 · Manufacture of other fertilizers and nitrogen compounds n.e.c",
  ),
  KeSicActivity(
      "201310",
      "Manufacture of plastics in primary forms",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2013 · Manufacture of plastics and synthetic rubber in primary forms / Subclass 20131 · Manufacture of plastics in primary forms",
  ),
  KeSicActivity(
      "201320",
      "Manufacture of synthetic rubber in primary forms",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2013 · Manufacture of plastics and synthetic rubber in primary forms / Subclass 20132 · Manufacture of synthetic rubber in primary forms",
  ),
  KeSicActivity(
      "201390",
      "Other Manufacture of plastics and synthetic rubber in primary forms n.e.c",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 201 · Manufacture of basic chemicals, fertilizers and nitrogen compounds, plastics and synthetic rubber in primary forms / Class 2013 · Manufacture of plastics and synthetic rubber in primary forms / Subclass 20139 · Other Manufacture of plastics and synthetic rubber in primary forms n.e.c",
  ),
  KeSicActivity(
      "202110",
      "Manufacture of insecticides, rodenticides, fungicides, herbicides",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2021 · Manufacture of pesticides and other agrochemical products / Subclass 20211 · Manufacture of insecticides, rodenticides, fungicides, herbicides",
  ),
  KeSicActivity(
      "202120",
      "Manufacture of anti-sprouting products, plant growth regulators",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2021 · Manufacture of pesticides and other agrochemical products / Subclass 20212 · Manufacture of anti-sprouting products, plant growth regulators",
  ),
  KeSicActivity(
      "202130",
      "Manufacture of disinfectants (for agricultural and other use)",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2021 · Manufacture of pesticides and other agrochemical products / Subclass 20213 · Manufacture of disinfectants (for agricultural and other use)",
  ),
  KeSicActivity(
      "202190",
      "Manufacture of other agrochemical products n.e.c",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2021 · Manufacture of pesticides and other agrochemical products / Subclass 20219 · Manufacture of other agrochemical products n.e.c",
  ),
  KeSicActivity(
      "202210",
      "Manufacture of paints and varnishes, enamels or lacquers",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2022 · Manufacture of paints, varnishes and similar coatings, printing ink and mastics / Subclass 20221 · Manufacture of paints and varnishes, enamels or lacquers",
  ),
  KeSicActivity(
      "202220",
      "Manufacture of caulking compounds and similar non-refractory filling or surfacing preparations",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2022 · Manufacture of paints, varnishes and similar coatings, printing ink and mastics / Subclass 20222 · Manufacture of caulking compounds and similar non-refractory filling or surfacing preparations",
  ),
  KeSicActivity(
      "202230",
      "Manufacture of printing ink",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2022 · Manufacture of paints, varnishes and similar coatings, printing ink and mastics / Subclass 20223 · Manufacture of printing ink",
  ),
  KeSicActivity(
      "202290",
      "Other manufacture of paints, varnishes and similar coatings, printing ink and mastics",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2022 · Manufacture of paints, varnishes and similar coatings, printing ink and mastics / Subclass 20229 · Other manufacture of paints, varnishes and similar coatings, printing ink and mastics",
  ),
  KeSicActivity(
      "202310",
      "Manufacture of soap",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2023 · Manufacture of soap and detergents, cleaning and polishing preparations, perfumes and toilet preparations / Subclass 20231 · Manufacture of soap",
  ),
  KeSicActivity(
      "202320",
      "Manufacture of surface-active preparations e.g. detergents",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2023 · Manufacture of soap and detergents, cleaning and polishing preparations, perfumes and toilet preparations / Subclass 20232 · Manufacture of surface-active preparations e.g. detergents",
  ),
  KeSicActivity(
      "202340",
      "Manufacture of cleaning and polishing products",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2023 · Manufacture of soap and detergents, cleaning and polishing preparations, perfumes and toilet preparations / Subclass 20234 · Manufacture of cleaning and polishing products",
  ),
  KeSicActivity(
      "202350",
      "Manufacture of perfumes and toilet preparations",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2023 · Manufacture of soap and detergents, cleaning and polishing preparations, perfumes and toilet preparations / Subclass 20235 · Manufacture of perfumes and toilet preparations",
  ),
  KeSicActivity(
      "202390",
      "Other manufacture of soap and detergents, cleaning and polishing preparations, perfumes and toilet preparations",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2023 · Manufacture of soap and detergents, cleaning and polishing preparations, perfumes and toilet preparations / Subclass 20239 · Other manufacture of soap and detergents, cleaning and polishing preparations, perfumes and toilet preparations",
  ),
  KeSicActivity(
      "202901",
      "Manufacture of gelatine and its derivatives, glues and prepared adhesives, including rubber-based glues and adhesives",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2029 · Manufacture of other chemical products n.e.c / Subclass 20290 · Manufacture of other chemical products n.e.c",
  ),
  KeSicActivity(
      "202902",
      "Manufacture of writing and drawing ink",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2029 · Manufacture of other chemical products n.e.c / Subclass 20290 · Manufacture of other chemical products n.e.c",
  ),
  KeSicActivity(
      "202903",
      "Manufacture of matches",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2029 · Manufacture of other chemical products n.e.c / Subclass 20290 · Manufacture of other chemical products n.e.c",
  ),
  KeSicActivity(
      "202909",
      "Manufacture of other chemical products n.e.c",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 202 · Manufacture of other chemical products / Class 2029 · Manufacture of other chemical products n.e.c / Subclass 20290 · Manufacture of other chemical products n.e.c",
  ),
  KeSicActivity(
      "203000",
      "Manufacture of man-made fibres",
      "Section C · Manufacturing / Division 20 · Manufacture of chemicals and chemical products / Group 203 · Manufacture of man-made fibres / Class 2030 · Manufacture of man-made fibres / Subclass 20300 · Manufacture of man-made fibres",
  ),
  KeSicActivity(
      "210010",
      "Manufacture of medicinal active substances",
      "Section C · Manufacturing / Division 21 · Manufacture of basic pharmaceutical products and pharmaceutical preparations / Group 210 · Manufacture of pharmaceuticals, medicinal chemical and botanical products / Class 2100 · Manufacture of pharmaceuticals, medicinal chemical and botanical products / Subclass 21001 · Manufacture of medicinal active substances",
  ),
  KeSicActivity(
      "210020",
      "Manufacture of medicaments",
      "Section C · Manufacturing / Division 21 · Manufacture of basic pharmaceutical products and pharmaceutical preparations / Group 210 · Manufacture of pharmaceuticals, medicinal chemical and botanical products / Class 2100 · Manufacture of pharmaceuticals, medicinal chemical and botanical products / Subclass 21002 · Manufacture of medicaments",
  ),
  KeSicActivity(
      "210030",
      "Manufacture of veterinary preparations",
      "Section C · Manufacturing / Division 21 · Manufacture of basic pharmaceutical products and pharmaceutical preparations / Group 210 · Manufacture of pharmaceuticals, medicinal chemical and botanical products / Class 2100 · Manufacture of pharmaceuticals, medicinal chemical and botanical products / Subclass 21003 · Manufacture of veterinary preparations",
  ),
  KeSicActivity(
      "210090",
      "Other manufacture of pharmaceuticals, medicinal chemical and botanical products n.e.c",
      "Section C · Manufacturing / Division 21 · Manufacture of basic pharmaceutical products and pharmaceutical preparations / Group 210 · Manufacture of pharmaceuticals, medicinal chemical and botanical products / Class 2100 · Manufacture of pharmaceuticals, medicinal chemical and botanical products / Subclass 21009 · Other manufacture of pharmaceuticals, medicinal chemical and botanical products n.e.c",
  ),
  KeSicActivity(
      "221110",
      "Manufacture of rubber tyres for vehicles, equipment, mobile machinery, aircraft, toy, furniture and other uses:",
      "Section C · Manufacturing / Division 22 · Manufacture of rubber and plastics products / Group 221 · Manufacture of rubber products / Class 2211 · Manufacture of rubber tyres and tubes; re- treading and rebuilding of rubber tyres / Subclass 22111 · Manufacture of rubber tyres for vehicles, equipment, mobile machinery, aircraft, toy, furniture and other uses:",
  ),
  KeSicActivity(
      "221120",
      "Tyre rebuilding and re-treading",
      "Section C · Manufacturing / Division 22 · Manufacture of rubber and plastics products / Group 221 · Manufacture of rubber products / Class 2211 · Manufacture of rubber tyres and tubes; re- treading and rebuilding of rubber tyres / Subclass 22112 · Tyre rebuilding and re-treading",
  ),
  KeSicActivity(
      "221190",
      "Other manufacture of rubber tyres and tubes products n.e.c",
      "Section C · Manufacturing / Division 22 · Manufacture of rubber and plastics products / Group 221 · Manufacture of rubber products / Class 2211 · Manufacture of rubber tyres and tubes; re- treading and rebuilding of rubber tyres / Subclass 22119 · Other manufacture of rubber tyres and tubes products n.e.c",
  ),
  KeSicActivity(
      "221900",
      "Manufacture of other rubber products",
      "Section C · Manufacturing / Division 22 · Manufacture of rubber and plastics products / Group 221 · Manufacture of rubber products / Class 2219 · Manufacture of other rubber products / Subclass 22190 · Manufacture of other rubber products",
  ),
  KeSicActivity(
      "222010",
      "Manufacture of finished plastic products",
      "Section C · Manufacturing / Division 22 · Manufacture of rubber and plastics products / Group 222 · Manufacture of plastics products / Class 2220 · Manufacture of plastics products / Subclass 22201 · Manufacture of finished plastic products",
  ),
  KeSicActivity(
      "222020",
      "Manufacture of builders’ plastics ware",
      "Section C · Manufacturing / Division 22 · Manufacture of rubber and plastics products / Group 222 · Manufacture of plastics products / Class 2220 · Manufacture of plastics products / Subclass 22202 · Manufacture of builders’ plastics ware",
  ),
  KeSicActivity(
      "222030",
      "Manufacture of plastic tableware, kitchenware and toilet articles",
      "Section C · Manufacturing / Division 22 · Manufacture of rubber and plastics products / Group 222 · Manufacture of plastics products / Class 2220 · Manufacture of plastics products / Subclass 22203 · Manufacture of plastic tableware, kitchenware and toilet articles",
  ),
  KeSicActivity(
      "222090",
      "Other manufacture of plastics products n.e.c",
      "Section C · Manufacturing / Division 22 · Manufacture of rubber and plastics products / Group 222 · Manufacture of plastics products / Class 2220 · Manufacture of plastics products / Subclass 22209 · Other manufacture of plastics products n.e.c",
  ),
  KeSicActivity(
      "231010",
      "Manufacture of flat glass",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 231 · Manufacture of glass and glass products / Class 2310 · Manufacture of glass and glass products / Subclass 23101 · Manufacture of flat glass",
  ),
  KeSicActivity(
      "231020",
      "Manufacture of glass mirrors",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 231 · Manufacture of glass and glass products / Class 2310 · Manufacture of glass and glass products / Subclass 23102 · Manufacture of glass mirrors",
  ),
  KeSicActivity(
      "231030",
      "Manufacture of bottles and other containers of glass or crystal and, drinking glasses and other domestic glass or crystal articles",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 231 · Manufacture of glass and glass products / Class 2310 · Manufacture of glass and glass products / Subclass 23103 · Manufacture of bottles and other containers of glass or crystal and, drinking glasses and other domestic glass or crystal articles",
  ),
  KeSicActivity(
      "231090",
      "Other manufacture of glass and glass products",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 231 · Manufacture of glass and glass products / Class 2310 · Manufacture of glass and glass products / Subclass 23109 · Other manufacture of glass and glass products",
  ),
  KeSicActivity(
      "239110",
      "Manufacture of refractory mortars, concretes etc",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2391 · Manufacture of refractory products / Subclass 23911 · Manufacture of refractory mortars, concretes etc",
  ),
  KeSicActivity(
      "239120",
      "Manufacture of refractory ceramic goods",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2391 · Manufacture of refractory products / Subclass 23912 · Manufacture of refractory ceramic goods",
  ),
  KeSicActivity(
      "239190",
      "Other manufacture of refractory products n.e.c",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2391 · Manufacture of refractory products / Subclass 23919 · Other manufacture of refractory products n.e.c",
  ),
  KeSicActivity(
      "239210",
      "Manufacture of structural non-refractory clay building materials",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2392 · Manufacture of clay building materials / Subclass 23921 · Manufacture of structural non-refractory clay building materials",
  ),
  KeSicActivity(
      "239220",
      "Manufacture of flooring blocks in baked clay",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2392 · Manufacture of clay building materials / Subclass 23922 · Manufacture of flooring blocks in baked clay",
  ),
  KeSicActivity(
      "239290",
      "Other manufacture of clay building materials",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2392 · Manufacture of clay building materials / Subclass 23929 · Other manufacture of clay building materials",
  ),
  KeSicActivity(
      "239300",
      "Manufacture of other porcelain and ceramic products",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2393 · Manufacture of other porcelain and ceramic products / Subclass 23930 · Manufacture of other porcelain and ceramic products",
  ),
  KeSicActivity(
      "239410",
      "Manufacture of clinkers and hydraulic cements, including Portland, aluminous cement, slag cement and superphosphate cements",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2394 · Manufacture of cement, lime and plaster / Subclass 23941 · Manufacture of clinkers and hydraulic cements, including Portland, aluminous cement, slag cement and superphosphate cements",
  ),
  KeSicActivity(
      "239420",
      "Manufacture of plasters of calcined gypsum or calcined sulphate",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2394 · Manufacture of cement, lime and plaster / Subclass 23942 · Manufacture of plasters of calcined gypsum or calcined sulphate",
  ),
  KeSicActivity(
      "239490",
      "Other manufacture of cement, lime and plaster n.e.c",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2394 · Manufacture of cement, lime and plaster / Subclass 23949 · Other manufacture of cement, lime and plaster n.e.c",
  ),
  KeSicActivity(
      "239510",
      "Manufacture of precast concrete, cement or artificial stone articles for use in construction",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2395 · Manufacture of articles of concrete, cement and plaster / Subclass 23951 · Manufacture of precast concrete, cement or artificial stone articles for use in construction",
  ),
  KeSicActivity(
      "239520",
      "Manufacture of prefabricated structural components for buildings or civil engineering of cement, concrete or artificial stone",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2395 · Manufacture of articles of concrete, cement and plaster / Subclass 23952 · Manufacture of prefabricated structural components for buildings or civil engineering of cement, concrete or artificial stone",
  ),
  KeSicActivity(
      "239530",
      "Manufacture of ready-mix and dry-mix concrete and mortars",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2395 · Manufacture of articles of concrete, cement and plaster / Subclass 23953 · Manufacture of ready-mix and dry-mix concrete and mortars",
  ),
  KeSicActivity(
      "239590",
      "Other manufacture of articles of concrete, cement and plaster",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2395 · Manufacture of articles of concrete, cement and plaster / Subclass 23959 · Other manufacture of articles of concrete, cement and plaster",
  ),
  KeSicActivity(
      "239610",
      "Cutting, shaping and finishing of stone for use in construction, in cemeteries, on roads, as roofing etc",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2396 · Cutting, shaping and finishing of stone / Subclass 23961 · Cutting, shaping and finishing of stone for use in construction, in cemeteries, on roads, as roofing etc",
  ),
  KeSicActivity(
      "239690",
      "Other cutting, shaping and finishing of stone n.e.c",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2396 · Cutting, shaping and finishing of stone / Subclass 23969 · Other cutting, shaping and finishing of stone n.e.c",
  ),
  KeSicActivity(
      "239900",
      "Manufactureofothernon-metallicmineral products n.e.c",
      "Section C · Manufacturing / Division 23 · Manufactureofothernon- -metallicmineral p products / Group 239 · Manufacture of non-metallic mineral products n.e.c / Class 2399 · Manufactureofothernon-metallicmineral products n.e.c / Subclass 23990 · Manufactureofothernon-metallicmineral products n.e.c",
  ),
  KeSicActivity(
      "241010",
      "Operation of blast furnaces, steel converters, rolling and finishing mills",
      "Section C · Manufacturing / Division 24 · Manufacture of basic metals / Group 241 · Manufacture of basic iron and steel / Class 2410 · Manufacture of basic iron and steel / Subclass 24101 · Operation of blast furnaces, steel converters, rolling and finishing mills",
  ),
  KeSicActivity(
      "241020",
      "Production of ferrous products by direct reduction of iron and other spongy ferrous e.g. steel bars products",
      "Section C · Manufacturing / Division 24 · Manufacture of basic metals / Group 241 · Manufacture of basic iron and steel / Class 2410 · Manufacture of basic iron and steel / Subclass 24102 · Production of ferrous products by direct reduction of iron and other spongy ferrous e.g. steel bars products",
  ),
  KeSicActivity(
      "241030",
      "Manufacture of wire of steel by cold drawing or stretching",
      "Section C · Manufacturing / Division 24 · Manufacture of basic metals / Group 241 · Manufacture of basic iron and steel / Class 2410 · Manufacture of basic iron and steel / Subclass 24103 · Manufacture of wire of steel by cold drawing or stretching",
  ),
  KeSicActivity(
      "241090",
      "Other manufacture of basic iron and steel n.e.c",
      "Section C · Manufacturing / Division 24 · Manufacture of basic metals / Group 241 · Manufacture of basic iron and steel / Class 2410 · Manufacture of basic iron and steel / Subclass 24109 · Other manufacture of basic iron and steel n.e.c",
  ),
  KeSicActivity(
      "242010",
      "Production and refining of unwrought or wrought precious metals: gold, silver, platinum etc. from ore and scrap",
      "Section C · Manufacturing / Division 24 · Manufacture of basic metals / Group 242 · Manufacture of basic precious and other non-ferrous metals / Class 2420 · Manufacture of basic precious and other non-ferrous metals / Subclass 24201 · Production and refining of unwrought or wrought precious metals: gold, silver, platinum etc. from ore and scrap",
  ),
  KeSicActivity(
      "242090",
      "Other manufacture of basic precious and other non-ferrous metals n.e.c",
      "Section C · Manufacturing / Division 24 · Manufacture of basic metals / Group 242 · Manufacture of basic precious and other non-ferrous metals / Class 2420 · Manufacture of basic precious and other non-ferrous metals / Subclass 24209 · Other manufacture of basic precious and other non-ferrous metals n.e.c",
  ),
  KeSicActivity(
      "243100",
      "Casting of iron and steel",
      "Section C · Manufacturing / Division 24 · Manufacture of basic metals / Group 243 · Casting of metals / Class 2431 · Casting of iron and steel / Subclass 24310 · Casting of iron and steel",
  ),
  KeSicActivity(
      "243200",
      "Casting of non-ferrous metals e.g. Aluminium",
      "Section C · Manufacturing / Division 24 · Manufacture of basic metals / Group 243 · Casting of metals / Class 2432 · Casting of non-ferrous metals / Subclass 24320 · Casting of non-ferrous metals e.g. Aluminium",
  ),
  KeSicActivity(
      "251110",
      "Manufacture of metal frameworks or skeletons for construction and parts thereof (towers, masts, trusses, bridges etc.)",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2511 · Manufacture of structural metal products / Subclass 25111 · Manufacture of metal frameworks or skeletons for construction and parts thereof (towers, masts, trusses, bridges etc.)",
  ),
  KeSicActivity(
      "251120",
      "Manufacture of metal doors, windows and their frames, shutters and gates",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2511 · Manufacture of structural metal products / Subclass 25112 · Manufacture of metal doors, windows and their frames, shutters and gates",
  ),
  KeSicActivity(
      "251130",
      "Manufacture of prefabricated buildings mainly of metal",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2511 · Manufacture of structural metal products / Subclass 25113 · Manufacture of prefabricated buildings mainly of metal",
  ),
  KeSicActivity(
      "251190",
      "Other manufacture of structural metal products",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2511 · Manufacture of structural metal products / Subclass 25119 · Other manufacture of structural metal products",
  ),
  KeSicActivity(
      "251210",
      "Manufacture of reservoirs, tanks and similar containers of metal, of types",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2512 · Manufacture of tanks, reservoirs and containers of metal / Subclass 25121 · Manufacture of reservoirs, tanks and similar containers of metal, of types normally installed as fixtures for storage or manufacturing use",
  ),
  KeSicActivity(
      "251220",
      "Manufacture of metal containers for compressed or liquefied gas",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2512 · Manufacture of tanks, reservoirs and containers of metal / Subclass 25122 · Manufacture of metal containers for compressed or liquefied gas",
  ),
  KeSicActivity(
      "251230",
      "Manufacture of central heating boilers and radiators",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2512 · Manufacture of tanks, reservoirs and containers of metal / Subclass 25123 · Manufacture of central heating boilers and radiators",
  ),
  KeSicActivity(
      "251290",
      "Other manufacture of tanks, reservoirs and containers of metal n.e.c",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2512 · Manufacture of tanks, reservoirs and containers of metal / Subclass 25129 · Other manufacture of tanks, reservoirs and containers of metal n.e.c",
  ),
  KeSicActivity(
      "251300",
      "Manufacture of steam generators, except central heating hot water boilers",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 251 · Manufacture of structural metal products, tanks, reservoirs and steam generators / Class 2513 · Manufacture of steam generators, except central heating hot water boilers / Subclass 25130 · Manufacture of steam generators, except central heating hot water boilers",
  ),
  KeSicActivity(
      "252000",
      "Manufacture of weapons and ammunition",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 252 · Manufacture of weapons and ammunition / Class 2520 · Manufacture of weapons and ammunition / Subclass 25200 · Manufacture of weapons and ammunition",
  ),
  KeSicActivity(
      "259100",
      "Forging, pressing, stamping and roll- forming of metal; powder metallurgy",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2591 · Forging, pressing, stamping and roll- forming of metal; powder metallurgy / Subclass 25910 · Forging, pressing, stamping and roll- forming of metal; powder metallurgy",
  ),
  KeSicActivity(
      "259200",
      "Treatment and coating of metals; machining",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2592 · Treatment and coating of metals; machining / Subclass 25920 · Treatment and coating of metals; machining",
  ),
  KeSicActivity(
      "259310",
      "Manufacture of cutlery such as knives, forks, spoons, cleavers, choppers, razors, razor blades, scissors, hair clippers etc",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2593 · Manufacture of cutlery, hand tools and general hardware / Subclass 25931 · Manufacture of cutlery such as knives, forks, spoons, cleavers, choppers, razors, razor blades, scissors, hair clippers etc",
  ),
  KeSicActivity(
      "259321",
      "Manufacture of hand tools such as pliers, screwdrivers, press tools, blacksmiths’ tools, drills, punches, milling cutters etc",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2593 · Manufacture of cutlery, hand tools and general hardware / Subclass 25932 · Manufacture of hand tools",
  ),
  KeSicActivity(
      "259322",
      "Manufacture of non-power-driven agricultural hand tools",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2593 · Manufacture of cutlery, hand tools and general hardware / Subclass 25932 · Manufacture of hand tools",
  ),
  KeSicActivity(
      "259330",
      "Manufacture of padlocks, locks, keys, hingesandthelike,hardwareforbuildings, furniture, vehicles etc",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2593 · Manufacture of cutlery, hand tools and general hardware / Subclass 25933 · Manufacture of padlocks, locks, keys, hingesandthe like,hardwareforbuildings, furniture, vehicles etc",
  ),
  KeSicActivity(
      "259340",
      "Manufacture of general hardware (saws and sawblades, including circular sawblades and chainsaw blades, moulding boxes, vices, clamps etc.)",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2593 · Manufacture of cutlery, hand tools and general hardware / Subclass 25934 · Manufacture of general hardware (saws and sawblades, including circular sawblades and chainsaw blades, moulding boxes, vices, clamps etc.)",
  ),
  KeSicActivity(
      "259350",
      "Manufacture of cutlasses, swords, bayonets etc",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2593 · Manufacture of cutlery, hand tools and general hardware / Subclass 25935 · Manufacture of cutlasses, swords, bayonets etc",
  ),
  KeSicActivity(
      "259390",
      "Other manufacture of cutlery, hand tools and general hardware",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2593 · Manufacture of cutlery, hand tools and general hardware / Subclass 25939 · Other manufacture of cutlery, hand tools and general hardware",
  ),
  KeSicActivity(
      "259910",
      "Manufacture of articles made of wire: barbed wire, wire fencing, grill, netting, cloth etc",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2599 · Manufacture of other fabricated metal products n.e.c / Subclass 25991 · Manufacture of articles made of wire: barbed wire, wire fencing, grill, netting, cloth etc",
  ),
  KeSicActivity(
      "259920",
      "Manufacture of metal fasteners (nails, rivets, tacks, pins, staples, washers, and similar non-threaded products and nuts, bolts, screws and other threaded products)",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2599 · Manufacture of other fabricated metal products n.e.c / Subclass 25992 · Manufacture of metal fasteners (nails, rivets, tacks, pins, staples, washers, and similar non-threaded products and nuts, bolts, screws and other threaded products)",
  ),
  KeSicActivity(
      "259930",
      "Manufacture of containers such as pails, drums, buckets, boxes tins and cans for food products and boxes",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2599 · Manufacture of other fabricated metal products n.e.c / Subclass 25993 · Manufacture of containers such as pails, drums, buckets, boxes tins and cans for food products and boxes",
  ),
  KeSicActivity(
      "259940",
      "Manufacture of metal household articles (plates, saucers, pots, kettles, saucepans, metal scouring pads, frying pans and other non-electrical utensils, small hand- operated kitchen appliances and accessories)",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2599 · Manufacture of other fabricated metal products n.e.c / Subclass 25994 · Manufacture of metal household articles (plates, saucers, pots, kettles, saucepans, metal scouring pads, frying pans and other non-electrical utensils, small hand- operated kitchen appliances and accessories)",
  ),
  KeSicActivity(
      "259950",
      "Manufacture of metal sanitaryware such as baths,sinks,washbasinsandsimilararticles",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2599 · Manufacture of other fabricated metal products n.e.c / Subclass 25995 · Manufacture of metal sanitaryware such as baths,sinks,washbasinsandsimilararticles",
  ),
  KeSicActivity(
      "259960",
      "Manufacture of reinforced safes, vaults, strongroom doors, gates and metal goods for office use (other than office furniture) and other purposes",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2599 · Manufacture of other fabricated metal products n.e.c / Subclass 25996 · Manufacture of reinforced safes, vaults, strongroom doors, gates and metal goods for office use (other than office furniture) and other purposes",
  ),
  KeSicActivity(
      "259990",
      "Other manufacture of other fabricated metal products n.e.c",
      "Section C · Manufacturing / Division 25 · Manufacture of fabricated metal products, except machinery and equipment / Group 259 · Manufacture of other fabricated metal products; metalworking service activities / Class 2599 · Manufacture of other fabricated metal products n.e.c / Subclass 25999 · Other manufacture of other fabricated metal products n.e.c",
  ),
  KeSicActivity(
      "261001",
      "Loading of components onto printed circuit boards",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 261 · Manufacture of electronic components and boards / Class 2610 · Manufacture of electronic components and boards / Subclass 26100 · Manufacture of electronic components and boards",
  ),
  KeSicActivity(
      "261009",
      "Other manufacture of electronic components and boards",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 261 · Manufacture of electronic components and boards / Class 2610 · Manufacture of electronic components and boards / Subclass 26100 · Manufacture of electronic components and boards",
  ),
  KeSicActivity(
      "262000",
      "Manufacture or assembling of computers and peripheral equipment",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 262 · Manufacture of computers and peripheral equipment / Class 2620 · Manufacture of computers and peripheral equipment / Subclass 26200 · Manufacture or assembling of computers and peripheral equipment",
  ),
  KeSicActivity(
      "263000",
      "Manufacture ofcommunication equipment",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 263 · Manufacture ofcommunication equipment / Class 2630 · Manufacture ofcommunication equipment / Subclass 26300 · Manufacture ofcommunication equipment",
  ),
  KeSicActivity(
      "264000",
      "Manufacture of consumer electronics e.g. television, speakers, DVD players, radio receivers etc",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 264 · Manufacture of consumer electronics / Class 2640 · Manufacture of consumer electronics / Subclass 26400 · Manufacture of consumer electronics",
  ),
  KeSicActivity(
      "265100",
      "Manufacture of measuring, testing, navigating and control equipment",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 265 · Manufacture of measuring, testing, navigatingandcontrolequipment;watches and clocks / Class 2651 · Manufacture of measuring, testing, navigating and control equipment / Subclass 26510 · Manufacture of measuring, testing, navigating and control equipment",
  ),
  KeSicActivity(
      "265200",
      "Manufacture of watches and clocks",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 265 · Manufacture of measuring, testing, navigatingandcontrolequipment;watches and clocks / Class 2652 · Manufacture of watches and clocks / Subclass 26520 · Manufacture of watches and clocks",
  ),
  KeSicActivity(
      "266000",
      "Manufacture of irradiation, electromedical and electrotherapeutic equipment",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 266 · Manufacture of irradiation, electromedical and electrotherapeutic equipment / Class 2660 · Manufacture of irradiation, electromedical and electrotherapeutic equipment / Subclass 26600 · Manufacture of irradiation, electromedical and electrotherapeutic equipment",
  ),
  KeSicActivity(
      "267000",
      "Manufacture of optical instruments and photographic equipment",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 267 · Manufacture of optical instruments and photographic equipment / Class 2670 · Manufacture of optical instruments and photographic equipment / Subclass 26700 · Manufacture of optical instruments and photographic equipment",
  ),
  KeSicActivity(
      "268000",
      "Manufactureofmagneticandopticalmedia",
      "Section C · Manufacturing / Division 26 · Manufacture of computer, electronic and optical products / Group 268 · Manufactureofmagneticandopticalmedia / Class 2680 · Manufactureofmagneticandopticalmedia / Subclass 26800 · Manufactureofmagneticandopticalmedia",
  ),
  KeSicActivity(
      "271000",
      "Manufacture ofelectric motors, generators, transformers and electricity distribution and control apparatus",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 271 · Manufacture ofelectric motors, generators, transformers and electricity distribution and control apparatus / Class 2710 · Manufactureofelectricmotors,generators, transformers and electricity distribution and control apparatus / Subclass 27100 · Manufacture ofelectric motors, generators, transformers and electricity distribution and control apparatus",
  ),
  KeSicActivity(
      "272010",
      "Manufacture of primary cells and primary batteries",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 272 · Manufacture of batteries and accumulators / Class 2720 · Manufacture of batteries and accumulators / Subclass 27201 · Manufacture of primary cells and primary batteries",
  ),
  KeSicActivity(
      "272090",
      "Other manufacture of batteries and accumulators",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 272 · Manufacture of batteries and accumulators / Class 2720 · Manufacture of batteries and accumulators / Subclass 27209 · Other manufacture of batteries and accumulators",
  ),
  KeSicActivity(
      "273100",
      "Manufacture of fibre optic cables",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 273 · Manufacture of wiring and wiring devices / Class 2731 · Manufacture of fibre optic cables / Subclass 27310 · Manufacture of fibre optic cables",
  ),
  KeSicActivity(
      "273200",
      "Manufacture of other electronic and electric wires and cables",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 273 · Manufacture of wiring and wiring devices / Class 2732 · Manufacture of other electronic and electric wires and cables / Subclass 27320 · Manufacture of other electronic and electric wires and cables",
  ),
  KeSicActivity(
      "273310",
      "Manufacture of switch, switch box, lamp holders, lugs etc",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 273 · Manufacture of wiring and wiring devices / Class 2733 · Manufacture of wiring devices / Subclass 27331 · Manufacture of switch, switch box, lamp holders, lugs etc",
  ),
  KeSicActivity(
      "273320",
      "Manufacture of electrical conduit and fitting",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 273 · Manufacture of wiring and wiring devices / Class 2733 · Manufacture of wiring devices / Subclass 27332 · Manufacture of electrical conduit and fitting",
  ),
  KeSicActivity(
      "273330",
      "Manufacture of plastic noncurrent- carrying wiring devices including plastic junction boxes, face plates, and similar, plastic pole line fittings",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 273 · Manufacture of wiring and wiring devices / Class 2733 · Manufacture of wiring devices / Subclass 27333 · Manufacture of plastic noncurrent- carrying wiring devices including plastic junction boxes, face plates, and similar, plastic pole line fittings",
  ),
  KeSicActivity(
      "273390",
      "Other manufacture of wiring devices n.e.c",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 273 · Manufacture of wiring and wiring devices / Class 2733 · Manufacture of wiring devices / Subclass 27339 · Other manufacture of wiring devices n.e.c",
  ),
  KeSicActivity(
      "274000",
      "Manufactureofelectriclightingequipment",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 274 · Manufactureofelectriclightingequipment / Class 2740 · Manufactureofelectriclightingequipment / Subclass 27400 · Manufactureofelectriclightingequipment",
  ),
  KeSicActivity(
      "275010",
      "Manufacture of domestic non-electric cooking and heating equipment such as non-electric space heaters, cooking ranges, grates, stoves, water heaters, cooking appliances, plate warmers",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 275 · Manufacture of domestic appliances / Class 2750 · Manufacture of domestic appliances / Subclass 27501 · Manufacture of domestic non-electric cooking and heating equipment such as non-electric space heaters, cooking ranges, grates, stoves, water heaters, cooking appliances, plate warmers",
  ),
  KeSicActivity(
      "275090",
      "Other manufacture of domestic appliances n.e.c",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 275 · Manufacture of domestic appliances / Class 2750 · Manufacture of domestic appliances / Subclass 27509 · Other manufacture of domestic appliances n.e.c",
  ),
  KeSicActivity(
      "279000",
      "Manufacture of other electrical equipment",
      "Section C · Manufacturing / Division 27 · Manufacture of electrical equipment / Group 279 · Manufacture of other electrical equipment / Class 2790 · Manufacture of other electrical equipment / Subclass 27900 · Manufacture of other electrical equipment",
  ),
  KeSicActivity(
      "281100",
      "Manufacture of engines and turbines, except aircraft, vehicle and cycle engines",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2811 · Manufacture of engines and turbines, except aircraft, vehicle and cycle engines / Subclass 28110 · Manufacture of engines and turbines, except aircraft, vehicle and cycle engines",
  ),
  KeSicActivity(
      "281200",
      "Manufacture of fluid power equipment",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2812 · Manufacture of fluid power equipment / Subclass 28120 · Manufacture of fluid power equipment",
  ),
  KeSicActivity(
      "281310",
      "Manufacture of hand pumps",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2813 · Manufacture of other pumps, compressors, taps and valves / Subclass 28131 · Manufacture of hand pumps",
  ),
  KeSicActivity(
      "281390",
      "Other manufacture of other pumps, compressors, taps and valves n.e.c",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2813 · Manufacture of other pumps, compressors, taps and valves / Subclass 28139 · Other manufacture of other pumps, compressors, taps and valves n.e.c",
  ),
  KeSicActivity(
      "281400",
      "Manufacture of bearings, gears, gearing and driving elements",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2814 · Manufacture of bearings, gears, gearing and driving elements / Subclass 28140 · Manufacture of bearings, gears, gearing and driving elements",
  ),
  KeSicActivity(
      "281500",
      "Manufacture of ovens, furnaces and furnace burners",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2815 · Manufacture of ovens, furnaces and furnace burners / Subclass 28150 · Manufacture of ovens, furnaces and furnace burners",
  ),
  KeSicActivity(
      "281600",
      "Manufacture of lifting and handling equipment",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2816 · Manufacture of lifting and handling equipment / Subclass 28160 · Manufacture of lifting and handling equipment",
  ),
  KeSicActivity(
      "281700",
      "Manufacture of office machinery and equipment (except computers and peripheral equipment)",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2817 · Manufacture of office machinery and equipment (except computers and peripheral equipment) / Subclass 28170 · Manufacture of office machinery and equipment (except computers and peripheral equipment)",
  ),
  KeSicActivity(
      "281800",
      "Manufacture of power-driven hand tools",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2818 · Manufacture of power-driven hand tools / Subclass 28180 · Manufacture of power-driven hand tools",
  ),
  KeSicActivity(
      "281910",
      "Manufacture of weighing machinery (other than sensitive laboratory balances):",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2819 · Manufacture of other general-purpose machinery / Subclass 28191 · Manufacture of weighing machinery (other than sensitive laboratory balances):",
  ),
  KeSicActivity(
      "281990",
      "Manufacture of other general-purpose machinery",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 281 · Manufacture of general-purpose machinery / Class 2819 · Manufacture of other general-purpose machinery / Subclass 28199 · Manufacture of other general-purpose machinery",
  ),
  KeSicActivity(
      "282110",
      "Manufacture ofploughs,manurespreaders, seeders, harrows and similar agricultural machinery for soil preparation, planting or fertilizing, harvesting or threshing machinery",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2821 · Manufacture of agricultural and forestry machinery / Subclass 28211 · Manufactureofploughs,manurespreaders, seeders, harrows and similar agricultural machinery for soil preparation, planting or fertilizing, harvesting or threshing machinery",
  ),
  KeSicActivity(
      "282120",
      "Manufacture of walking (pedestrian- controlled) tractors",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2821 · Manufacture of agricultural and forestry machinery / Subclass 28212 · Manufacture of walking (pedestrian- controlled) tractors",
  ),
  KeSicActivity(
      "282130",
      "Manufacture of diverse agricultural machinery such as poultry-keeping machinery",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2821 · Manufacture of agricultural and forestry machinery / Subclass 28213 · Manufacture of diverse agricultural machinery such as poultry-keeping machinery",
  ),
  KeSicActivity(
      "282190",
      "Other manufacture of agricultural and forestry machinery n.e.c",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2821 · Manufacture of agricultural and forestry machinery / Subclass 28219 · Other manufacture of agricultural and forestry machinery n.e.c",
  ),
  KeSicActivity(
      "282200",
      "Manufacture of metal-forming machinery and machine tools",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2822 · Manufacture of metal-forming machinery and machine tools / Subclass 28220 · Manufacture of metal-forming machinery and machine tools",
  ),
  KeSicActivity(
      "282300",
      "Manufacture of machinery for metallurgy",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2823 · Manufacture of machinery for metallurgy / Subclass 28230 · Manufacture of machinery for metallurgy",
  ),
  KeSicActivity(
      "282400",
      "Manufacture of machinery for mining, quarrying and construction",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2824 · Manufacture of machinery for mining, quarrying and construction / Subclass 28240 · Manufacture of machinery for mining, quarrying and construction",
  ),
  KeSicActivity(
      "282510",
      "Manufacture of machinery for the grain milling industry:",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2825 · Manufacture of machinery for food, beverage and tobacco processing / Subclass 28251 · Manufacture of machinery for the grain milling industry:",
  ),
  KeSicActivity(
      "282520",
      "Manufacture of presses, crushers etc. used to make wine, cider, fruit juices etc",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2825 · Manufacture of machinery for food, beverage and tobacco processing / Subclass 28252 · Manufacture of presses, crushers etc. used to make wine, cider, fruit juices etc",
  ),
  KeSicActivity(
      "282530",
      "Manufacture of machinery for the bakery industry or for making macaroni, spaghetti or similar products",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2825 · Manufacture of machinery for food, beverage and tobacco processing / Subclass 28253 · Manufacture of machinery for the bakery industry or for making macaroni, spaghetti or similar products",
  ),
  KeSicActivity(
      "282590",
      "Other manufacture of machinery for food, beverage and tobacco processing",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2825 · Manufacture of machinery for food, beverage and tobacco processing / Subclass 28259 · Other manufacture of machinery for food, beverage and tobacco processing",
  ),
  KeSicActivity(
      "282610",
      "Manufacture of textile machinery such as weaving machines (looms), including hand looms",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2826 · Manufacture of machinery for textile, apparel and leather production / Subclass 28261 · Manufacture of textile machinery such as weaving machines (looms), including hand looms",
  ),
  KeSicActivity(
      "282690",
      "Other manufacture of machinery for textile, apparel and leather production n.e.c",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2826 · Manufacture of machinery for textile, apparel and leather production / Subclass 28269 · Other manufacture of machinery for textile, apparel and leather production n.e.c",
  ),
  KeSicActivity(
      "282900",
      "Manufacture of other special-purpose machinery",
      "Section C · Manufacturing / Division 28 · Manufacture of m machinery and equipment n.e.c / Group 282 · Processing and preservation of fruit food products and juices including concentrates Processing and preservation of fruit food products and juices including concentrates / Class 2829 · Manufacture of other special-purpose machinery / Subclass 28290 · Manufacture of other special-purpose machinery",
  ),
  KeSicActivity(
      "291001",
      "Manufacture of passenger and commercial cars",
      "Section C · Manufacturing / Division 29 · Manufacture of motor vehicles, trailers and semi- -trailers / Group 291 · Manufacture of motor vehicles / Class 2910 · Manufacture of motor vehicles / Subclass 29100 · Manufacture or assembling of motor vehicles",
  ),
  KeSicActivity(
      "291002",
      "Assembling of motor vehicles",
      "Section C · Manufacturing / Division 29 · Manufacture of motor vehicles, trailers and semi- -trailers / Group 291 · Manufacture of motor vehicles / Class 2910 · Manufacture of motor vehicles / Subclass 29100 · Manufacture or assembling of motor vehicles",
  ),
  KeSicActivity(
      "292010",
      "Manufacture of bodies (coachwork) for motor vehicles;",
      "Section C · Manufacturing / Division 29 · Manufacture of motor vehicles, trailers and semi- -trailers / Group 292 · Manufacture of bodies (coachwork) for motor vehicles; manufacture of trailers and semi-trailers / Class 2920 · Manufacture of bodies (coachwork) for motor vehicles; manufacture of trailers and semi-trailers / Subclass 29201 · Manufacture of bodies (coachwork) for motor vehicles;",
  ),
  KeSicActivity(
      "292020",
      "Manufacture of trailers and semi-trailers",
      "Section C · Manufacturing / Division 29 · Manufacture of motor vehicles, trailers and semi- -trailers / Group 292 · Manufacture of bodies (coachwork) for motor vehicles; manufacture of trailers and semi-trailers / Class 2920 · Manufacture of bodies (coachwork) for motor vehicles; manufacture of trailers and semi-trailers / Subclass 29202 · Manufacture of trailers and semi-trailers",
  ),
  KeSicActivity(
      "293010",
      "Manufacture of diverse parts and accessories for motor vehicles such as brakes, gearboxes, axles, road wheels, suspension shock absorbers, radiators, silencers, exhaust pipes, catalysers, clutches, steering wheels, steering columns and steering boxes etc",
      "Section C · Manufacturing / Division 29 · Manufacture of motor vehicles, trailers and semi- -trailers / Group 293 · Manufacture of parts and accessories for motor vehicles / Class 2930 · Manufacture of parts and accessories for motor vehicles / Subclass 29301 · Manufacture of diverse parts and accessories for motor vehicles such as brakes, gearboxes, axles, road wheels,",
  ),
  KeSicActivity(
      "293020",
      "Manufacture of car seats",
      "Section C · Manufacturing / Division 29 · Manufacture of motor vehicles, trailers and semi- -trailers / Group 293 · Manufacture of parts and accessories for motor vehicles / Class 2930 · Manufacture of parts and accessories for motor vehicles / Subclass 29302 · Manufacture of car seats",
  ),
  KeSicActivity(
      "293090",
      "Other manufacture of parts and accessories for motor vehicles",
      "Section C · Manufacturing / Division 29 · Manufacture of motor vehicles, trailers and semi- -trailers / Group 293 · Manufacture of parts and accessories for motor vehicles / Class 2930 · Manufacture of parts and accessories for motor vehicles / Subclass 29309 · Other manufacture of parts and accessories for motor vehicles",
  ),
  KeSicActivity(
      "301100",
      "Building of ships and floating structures",
      "Section C · Manufacturing / Division 30 · Manufacture of other transport e equipment / Group 301 · Building of ships and boats / Class 3011 · Building of ships and floating structures / Subclass 30110 · Building of ships and floating structures",
  ),
  KeSicActivity(
      "301200",
      "Building of pleasure and sporting boats",
      "Section C · Manufacturing / Division 30 · Manufacture of other transport e equipment / Group 301 · Building of ships and boats / Class 3012 · Building of pleasure and sporting boats / Subclass 30120 · Building of pleasure and sporting boats",
  ),
  KeSicActivity(
      "302000",
      "Manufacture of railway locomotives and rolling stock",
      "Section C · Manufacturing / Division 30 · Manufacture of other transport e equipment / Group 302 · Manufacture of railway locomotives and rolling stock / Class 3020 · Manufacture of railway locomotives and rolling stock / Subclass 30200 · Manufacture of railway locomotives and rolling stock",
  ),
  KeSicActivity(
      "303000",
      "Manufacture of air and spacecraft and related machinery",
      "Section C · Manufacturing / Division 30 · Manufacture of other transport e equipment / Group 303 · Manufacture of air and spacecraft and related machinery / Class 3030 · Manufacture of air and spacecraft and related machinery / Subclass 30300 · Manufacture of air and spacecraft and related machinery",
  ),
  KeSicActivity(
      "304000",
      "Manufacture of military fighting vehicles",
      "Section C · Manufacturing / Division 30 · Manufacture of other transport e equipment / Group 304 · Manufacture of military fighting vehicles / Class 3040 · Manufacture of military fighting vehicles / Subclass 30400 · Manufacture of military fighting vehicles",
  ),
  KeSicActivity(
      "309100",
      "Manufacture and assembling of motorcycles",
      "Section C · Manufacturing / Division 30 · Manufacture of other transport e equipment / Group 309 · Manufacture of transport equipment n.e.c / Class 3091 · Manufacture of motorcycles / Subclass 30910 · Manufacture and assembling of motorcycles",
  ),
  KeSicActivity(
      "309200",
      "Manufacture of bicycles and invalid carriages",
      "Section C · Manufacturing / Division 30 · Manufacture of other transport e equipment / Group 309 · Manufacture of transport equipment n.e.c / Class 3092 · Manufacture of bicycles and invalid carriages / Subclass 30920 · Manufacture of bicycles and invalid carriages",
  ),
  KeSicActivity(
      "309900",
      "Manufacture of other transport equipment n.e.c",
      "Section C · Manufacturing / Division 30 · Manufacture of other transport e equipment / Group 309 · Manufacture of transport equipment n.e.c / Class 3099 · Manufacture of other transport equipment n.e.c / Subclass 30990 · Manufacture of other transport equipment n.e.c",
  ),
  KeSicActivity(
      "310010",
      "Manufacture of furniture made of wood",
      "Section C · Manufacturing / Division 31 · Manufacture of furniture / Group 310 · Manufacture of furniture / Class 3100 · Manufacture of furniture (excluding medical furniture see 3250) / Subclass 31001 · Manufacture of furniture made of wood",
  ),
  KeSicActivity(
      "310020",
      "Manufacture of furniture primarily of metal",
      "Section C · Manufacturing / Division 31 · Manufacture of furniture / Group 310 · Manufacture of furniture / Class 3100 · Manufacture of furniture (excluding medical furniture see 3250) / Subclass 31002 · Manufacture of furniture primarily of metal",
  ),
  KeSicActivity(
      "310030",
      "Manufacture of furniture primarily of plastic",
      "Section C · Manufacturing / Division 31 · Manufacture of furniture / Group 310 · Manufacture of furniture / Class 3100 · Manufacture of furniture (excluding medical furniture see 3250) / Subclass 31003 · Manufacture of furniture primarily of plastic",
  ),
  KeSicActivity(
      "310040",
      "Manufacture of mattresses and pillows",
      "Section C · Manufacturing / Division 31 · Manufacture of furniture / Group 310 · Manufacture of furniture / Class 3100 · Manufacture of furniture (excluding medical furniture see 3250) / Subclass 31004 · Manufacture of mattresses and pillows",
  ),
  KeSicActivity(
      "310090",
      "Manufacture of other furniture n.e.c",
      "Section C · Manufacturing / Division 31 · Manufacture of furniture / Group 310 · Manufacture of furniture / Class 3100 · Manufacture of furniture (excluding medical furniture see 3250) / Subclass 31009 · Manufacture of other furniture n.e.c",
  ),
  KeSicActivity(
      "321100",
      "Manufacture of jewellery and related articles",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 321 · Manufacture of jewellery, bijouterie and related articles / Class 3211 · Manufacture of jewellery and related articles / Subclass 32110 · Manufacture of jewellery and related articles",
  ),
  KeSicActivity(
      "321200",
      "Manufacture of imitation jewellery and related articles",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 321 · Manufacture of jewellery, bijouterie and related articles / Class 3212 · Manufacture of imitation jewellery and related articles / Subclass 32120 · Manufacture of imitation jewellery and related articles",
  ),
  KeSicActivity(
      "322000",
      "Manufacture of musical instruments",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 322 · Manufacture of musical instruments / Class 3220 · Manufacture of musical instruments / Subclass 32200 · Manufacture of musical instruments",
  ),
  KeSicActivity(
      "323000",
      "Manufacture of sports goods",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 323 · Manufacture of sports goods / Class 3230 · Manufacture of sports goods / Subclass 32300 · Manufacture of sports goods",
  ),
  KeSicActivity(
      "324000",
      "Manufacture of games and toys",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 324 · Manufacture of games and toys / Class 3240 · Manufacture of games and toys / Subclass 32400 · Manufacture of games and toys",
  ),
  KeSicActivity(
      "325000",
      "Manufacture of medical and dental instruments and supplies",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 325 · Manufacture of medical and dental instruments and supplies / Class 3250 · Manufacture of medical and dental instruments and supplies / Subclass 32500 · Manufacture of medical and dental instruments and supplies",
  ),
  KeSicActivity(
      "329010",
      "Manufacture of brooms and brushes, including brushes constituting parts of machines, hand-operated mechanical floor sweepers, mops and feather dusters, paint brushes, paint pads and rollers, squeegees and other brushes, brooms, mops etc",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 329 · Other manufacturing n.e.c / Class 3290 · Other manufacturing n.e.c / Subclass 32901 · Manufacture of brooms and brushes, including brushes constituting parts of machines, hand-operated mechanical floor sweepers, mops and feather dusters, paint brushes, paint pads and rollers, squeegees and other brushes, brooms, mops etc",
  ),
  KeSicActivity(
      "329020",
      "Manufacture of stationary articles n.e.c such as pens and pencils of all kinds whether or not mechanical, pencil leads, date, sealing or numbering stamps, hand- operated devices for printing or embossing labels, hand printing sets, prepared typewriter ribbons and inked pads, globes etc",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 329 · Other manufacturing n.e.c / Class 3290 · Other manufacturing n.e.c / Subclass 32902 · Manufacture of stationary articles n.e.c such as pens and pencils of all kinds whether or not mechanical, pencil leads, date, sealing or numbering stamps, hand- operated devices for printing or embossing labels, hand printing sets, prepared typewriter ribbons and inked pads, globes etc",
  ),
  KeSicActivity(
      "329030",
      "Manufacture of articles of personal use: smoking pipes, scent sprays, vacuum flasks and other vacuum vessels for personal or householduse,wigs,false beards,eyebrows",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 329 · Other manufacturing n.e.c / Class 3290 · Other manufacturing n.e.c / Subclass 32903 · Manufacture of articles of personal use: smoking pipes, scent sprays, vacuum flasks and other vacuum vessels for personal or householduse,wigs,false beards,eyebrows",
  ),
  KeSicActivity(
      "329090",
      "Other manufacturing n.e.c",
      "Section C · Manufacturing / Division 32 · Other manufacturing / Group 329 · Other manufacturing n.e.c / Class 3290 · Other manufacturing n.e.c / Subclass 32909 · Other manufacturing n.e.c",
  ),
  KeSicActivity(
      "331100",
      "Repair of fabricated metal products",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3311 · Repair of fabricated metal products / Subclass 33110 · Repair of fabricated metal products",
  ),
  KeSicActivity(
      "331210",
      "Repair and maintenance of engines and turbines excluding aircraft, vehicle and cycle engines",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3312 · Repair of machinery / Subclass 33121 · Repair and maintenance of engines and turbines excluding aircraft, vehicle and cycle engines",
  ),
  KeSicActivity(
      "331220",
      "Repair and maintenance of pumps and related equipment, fluid power equipment, valves",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3312 · Repair of machinery / Subclass 33122 · Repair and maintenance of pumps and related equipment, fluid power equipment, valves",
  ),
  KeSicActivity(
      "331230",
      "Repair and maintenance of metal cutting and metal forming machine tools and accessories, power-driven hand-tools and other machine tools",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3312 · Repair of machinery / Subclass 33123 · Repair and maintenance of metal cutting and metal forming machine tools and accessories, power-driven hand-tools and other machine tools",
  ),
  KeSicActivity(
      "331240",
      "Repair and maintenance of agricultural machinery and forestry and logging machinery including agricultural tractors",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3312 · Repair of machinery / Subclass 33124 · Repair and maintenance of agricultural machinery and forestry and logging machinery including agricultural tractors",
  ),
  KeSicActivity(
      "331250",
      "Repair and maintenance of mining, construction, and oil and gas field machinery; metallurgy machinery",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3312 · Repair of machinery / Subclass 33125 · Repair and maintenance of mining, construction, and oil and gas field machinery; metallurgy machinery",
  ),
  KeSicActivity(
      "331260",
      "Repair and maintenance of food, beverage, and tobacco processing machinery",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3312 · Repair of machinery / Subclass 33126 · Repair and maintenance of food, beverage, and tobacco processing machinery",
  ),
  KeSicActivity(
      "331290",
      "Other repair of machinery n.e.c",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3312 · Repair of machinery / Subclass 33129 · Other repair of machinery n.e.c",
  ),
  KeSicActivity(
      "331300",
      "Repair of electronic and optical equipment",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3313 · Repair of electronic and optical equipment / Subclass 33130 · Repair of electronic and optical equipment",
  ),
  KeSicActivity(
      "331410",
      "Repair and maintenance of electric motors, generators, and motor generator sets",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3314 · Repair of electrical equipment / Subclass 33141 · Repair and maintenance of electric motors, generators, and motor generator sets",
  ),
  KeSicActivity(
      "331490",
      "Other repair of electrical equipment",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3314 · Repair of electrical equipment / Subclass 33149 · Other repair of electrical equipment",
  ),
  KeSicActivity(
      "331510",
      "Repair and routine maintenance of ships and boats",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3315 · Repair of transport equipment, except motor vehicles / Subclass 33151 · Repair and routine maintenance of ships and boats",
  ),
  KeSicActivity(
      "331520",
      "Repair and maintenance of locomotives and railroad cars (except factory rebuilding or factory conversion)",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3315 · Repair of transport equipment, except motor vehicles / Subclass 33152 · Repair and maintenance of locomotives and railroad cars (except factory rebuilding or factory conversion)",
  ),
  KeSicActivity(
      "331530",
      "Repair and maintenance of aircraft (except factory conversion, factory overhaul, factory rebuilding)",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3315 · Repair of transport equipment, except motor vehicles / Subclass 33153 · Repair and maintenance of aircraft (except factory conversion, factory overhaul, factory rebuilding)",
  ),
  KeSicActivity(
      "331590",
      "Other repair of transport equipment, except motor vehicles",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3315 · Repair of transport equipment, except motor vehicles / Subclass 33159 · Other repair of transport equipment, except motor vehicles",
  ),
  KeSicActivity(
      "331900",
      "Repair of other equipment",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 331 · Repair of fabricated metal products, machinery and equipment / Class 3319 · Repair of other equipment / Subclass 33190 · Repair of other equipment",
  ),
  KeSicActivity(
      "332010",
      "Installation of industrial machinery in industrial plant",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 332 · Installation of industrial machinery and equipment / Class 3320 · Installation of industrial machinery and equipment / Subclass 33201 · Installation of industrial machinery in industrial plant",
  ),
  KeSicActivity(
      "332020",
      "Installation of industrial process control equipment",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 332 · Installation of industrial machinery and equipment / Class 3320 · Installation of industrial machinery and equipment / Subclass 33202 · Installation of industrial process control equipment",
  ),
  KeSicActivity(
      "332030",
      "Installation of communication equipment e.g. broadcast equipment",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 332 · Installation of industrial machinery and equipment / Class 3320 · Installation of industrial machinery and equipment / Subclass 33203 · Installation of communication equipment e.g. broadcast equipment",
  ),
  KeSicActivity(
      "332090",
      "Installation of other industrial equipment n.e.c",
      "Section C · Manufacturing / Division 33 · Repair and installation of machinery and equipment / Group 332 · Installation of industrial machinery and equipment / Class 3320 · Installation of industrial machinery and equipment / Subclass 33209 · Installation of other industrial equipment n.e.c",
  ),
  KeSicActivity(
      "351011",
      "Electric power generation by hydroelectric power plants",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35101 · Electric power generation",
  ),
  KeSicActivity(
      "351012",
      "Electric power generation by non-coal based thermal (e.g. diesel, gas )",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35101 · Electric power generation",
  ),
  KeSicActivity(
      "351013",
      "Electric power generation using solar energy",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35101 · Electric power generation",
  ),
  KeSicActivity(
      "351014",
      "Electric power generation using other non- conventional sources",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35101 · Electric power generation",
  ),
  KeSicActivity(
      "351019",
      "Other sources of electric power generation",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35101 · Electric power generation",
  ),
  KeSicActivity(
      "351020",
      "Electric power transmission",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35102 · Electric power transmission",
  ),
  KeSicActivity(
      "351030",
      "Electric power distribution",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35103 · Electric power distribution",
  ),
  KeSicActivity(
      "351040",
      "Electric power generation using solar energy",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35104 · Electric power generation using solar energy",
  ),
  KeSicActivity(
      "351090",
      "Other electric power generation, transmission and distribution",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 351 · Electric power generation, transmission and distribution / Class 3510 · Electric power generation, transmission and distribution / Subclass 35109 · Other electric power generation, transmission and distribution",
  ),
  KeSicActivity(
      "352010",
      "Manufacture of gas; distribution of gaseous fuels through mains",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 352 · Manufacture of gas; distribution of gaseous fuels through mains / Class 3520 · Manufacture of gas; distribution of gaseous fuels through mains / Subclass 35201 · Manufacture of gas; distribution of gaseous fuels through mains",
  ),
  KeSicActivity(
      "352020",
      "Other related services(e.g. arranging for sale of natural gas)",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 352 · Manufacture of gas; distribution of gaseous fuels through mains / Class 3520 · Manufacture of gas; distribution of gaseous fuels through mains / Subclass 35202 · Other related services(e.g. arranging for sale of natural gas)",
  ),
  KeSicActivity(
      "353010",
      "Production of ice, including ice for food and non-food (e.g. cooling) purposes",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 353 · Steam and air conditioning supply / Class 3530 · Steam and air conditioning supply / Subclass 35301 · Production of ice, including ice for food and non-food (e.g. cooling) purposes",
  ),
  KeSicActivity(
      "353090",
      "Other steam and air conditioning supply",
      "Section D · Electricity, gas, steam and air conditioning supply / Division 35 · Electricity, gas, steam and air conditioning supply / Group 353 · Steam and air conditioning supply / Class 3530 · Steam and air conditioning supply / Subclass 35309 · Other steam and air conditioning supply",
  ),
  KeSicActivity(
      "360001",
      "distribution of water through mains, by trucks or other means",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 36 · Water collection, treatment and supply / Group 360 · Water collection, treatment and supply / Class 3600 · Water collection, treatment and supply / Subclass 36000 · Water collection, treatment and supply",
  ),
  KeSicActivity(
      "360002",
      "operation of irrigation canals",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 36 · Water collection, treatment and supply / Group 360 · Water collection, treatment and supply / Class 3600 · Water collection, treatment and supply / Subclass 36000 · Water collection, treatment and supply",
  ),
  KeSicActivity(
      "360009",
      "Other water collection, treatment and supply e.g. rain water, etc",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 36 · Water collection, treatment and supply / Group 360 · Water collection, treatment and supply / Class 3600 · Water collection, treatment and supply / Subclass 36000 · Water collection, treatment and supply",
  ),
  KeSicActivity(
      "370010",
      "The operation and maintenance of sewer systems",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 37 · Sewerage / Group 370 · Sewerage / Class 3700 · Sewerage / Subclass 37001 · The operation and maintenance of sewer systems",
  ),
  KeSicActivity(
      "370020",
      "Collecting and transporting of human or industrial waste water or rain water by means of sewerage networks, collectors, tanks and other means of transport (sewage vehicles etc.)",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 37 · Sewerage / Group 370 · Sewerage / Class 3700 · Sewerage / Subclass 37002 · Collecting and transporting of human or industrial waste water or rain water by means of sewerage networks, collectors, tanks and other means of transport (sewage vehicles etc.)",
  ),
  KeSicActivity(
      "370030",
      "Treatment of waste water or sewer by means of physical, chemical or biological processes",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 37 · Sewerage / Group 370 · Sewerage / Class 3700 · Sewerage / Subclass 37003 · Treatment of waste water or sewer by means of physical, chemical or biological processes",
  ),
  KeSicActivity(
      "381110",
      "Collection of non-hazardous solid waste (i.e. garbage) within a local area, such as collection of waste from households and businesses by means of refuse bins, wheeled bins, containers etc., may include mixed recoverable materials",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 38 · Waste collection, treatment and disposal activities; materials recovery / Group 381 · Waste collection / Class 3811 · Collection of non-hazardous waste / Subclass 38111 · Collection of non-hazardous solid waste (i.e. garbage) within a local area, such as collection of waste from households and businesses by means of refuse bins, wheeled bins, containers etc., may include mixed recoverable materials",
  ),
  KeSicActivity(
      "381120",
      "collection of recyclable materials",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 38 · Waste collection, treatment and disposal activities; materials recovery / Group 381 · Waste collection / Class 3811 · Collection of non-hazardous waste / Subclass 38112 · collection of recyclable materials",
  ),
  KeSicActivity(
      "381190",
      "Other collection of non-hazardous waste",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 38 · Waste collection, treatment and disposal activities; materials recovery / Group 381 · Waste collection / Class 3811 · Collection of non-hazardous waste / Subclass 38119 · Collection of other non-hazardous waste",
  ),
  KeSicActivity(
      "381200",
      "Collection of hazardous waste",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 38 · Waste collection, treatment and disposal activities; materials recovery / Group 381 · Waste collection / Class 3812 · Collection of hazardous waste",
  ),
  KeSicActivity(
      "381220",
      "operation of waste transfer stations for hazardous waste",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 38 · Waste collection, treatment and disposal activities; materials recovery / Group 381 · Waste collection / Class 3812 · Collection of hazardous waste / Subclass 38122 · operation of waste transfer stations for hazardous waste",
  ),
  KeSicActivity(
      "382100",
      "Treatment and disposal of non-hazardous waste",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 38 · Waste collection, treatment and disposal activities; materials recovery / Group 382 · Waste treatment and disposal / Class 3821 · Treatment and disposal of non-hazardous waste / Subclass 38210 · Treatment and disposal of non-hazardous waste",
  ),
  KeSicActivity(
      "382200",
      "Treatment and disposal of hazardous waste",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 38 · Waste collection, treatment and disposal activities; materials recovery / Group 382 · Waste treatment and disposal / Class 3822 · Treatment and disposal of hazardous waste / Subclass 38220 · Treatment and disposal of hazardous waste",
  ),
  KeSicActivity(
      "383000",
      "Materials recovery",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 38 · Waste collection, treatment and disposal activities; materials recovery / Group 383 · Materials recovery / Class 3830 · Materials recovery / Subclass 38300 · Materials recovery",
  ),
  KeSicActivity(
      "390000",
      "Remediation activities and other waste management services",
      "Section E · Water supply; sewerage, waste management and remediation activities / Division 39 · Remediation activities and other waste management services / Group 390 · Remediation activities and other waste management services / Class 3900 · Remediation activities and other waste management services / Subclass 39000 · Remediation activities and other waste management services",
  ),
  KeSicActivity(
      "410010",
      "Construction of all types of residential buildings",
      "Section F · Construction / Division 41 · Construction of buildings / Group 410 · Construction of buildings / Class 4100 · Construction of buildings / Subclass 41001 · Construction of all types of residential buildings",
  ),
  KeSicActivity(
      "410020",
      "Construction of all types of non-residential buildings",
      "Section F · Construction / Division 41 · Construction of buildings / Group 410 · Construction of buildings / Class 4100 · Construction of buildings / Subclass 41002 · Construction of all types of non-residential buildings",
  ),
  KeSicActivity(
      "410030",
      "Assembly and erection of prefabricated constructions on the site",
      "Section F · Construction / Division 41 · Construction of buildings / Group 410 · Construction of buildings / Class 4100 · Construction of buildings / Subclass 41003 · Assembly and erection of prefabricated constructions on the site",
  ),
  KeSicActivity(
      "421010",
      "Construction of motorways, streets, roads, other vehicular and pedestrian ways",
      "Section F · Construction / Division 42 · C Civil engineering / Group 421 · Construction of roads and railways / Class 4210 · Construction of roads and railways / Subclass 42101 · Construction of motorways, streets, roads, other vehicular and pedestrian ways",
  ),
  KeSicActivity(
      "421020",
      "Surface work on streets, roads, highways, bridges or tunnels",
      "Section F · Construction / Division 42 · C Civil engineering / Group 421 · Construction of roads and railways / Class 4210 · Construction of roads and railways / Subclass 42102 · Surface work on streets, roads, highways, bridges or tunnels",
  ),
  KeSicActivity(
      "421030",
      "Construction of bridges, including those for elevated highways",
      "Section F · Construction / Division 42 · C Civil engineering / Group 421 · Construction of roads and railways / Class 4210 · Construction of roads and railways / Subclass 42103 · Construction of bridges, including those for elevated highways",
  ),
  KeSicActivity(
      "421040",
      "Construction of railways and subways",
      "Section F · Construction / Division 42 · C Civil engineering / Group 421 · Construction of roads and railways / Class 4210 · Construction of roads and railways / Subclass 42104 · Construction of railways and subways",
  ),
  KeSicActivity(
      "421090",
      "Other construction of roads and railways",
      "Section F · Construction / Division 42 · C Civil engineering / Group 421 · Construction of roads and railways / Class 4210 · Construction of roads and railways / Subclass 42109 · Other construction of roads and railways",
  ),
  KeSicActivity(
      "422111",
      "Construction of power distribution lines",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42211 · Construction of powerlines",
  ),
  KeSicActivity(
      "422112",
      "Construction of power transmission lines",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42211 · Construction of powerlines",
  ),
  KeSicActivity(
      "422121",
      "Construction of pipelines",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42212 · Construction of pipelines and communication lines",
  ),
  KeSicActivity(
      "422122",
      "Construction of communication lines",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42212 · Construction of pipelines and communication lines",
  ),
  KeSicActivity(
      "422130",
      "Water main and line construction and irrigation systems (canals)",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42213 · Water main and line construction and irrigation systems (canals)",
  ),
  KeSicActivity(
      "422140",
      "Construction of reservoirs e.g. water tanks, treatment plants, bulk water storage tanks installation",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42214 · Construction of reservoirs",
  ),
  KeSicActivity(
      "422151",
      "Construction of sewer systems, including repair and sewage disposal plants",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42215 · Construction of sewer systems, including repair and sewage disposal plants",
  ),
  KeSicActivity(
      "422152",
      "Construction of domestic sewers(Biodigester/septic tanks)",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42215 · Construction of sewer systems, including repair and sewage disposal plants",
  ),
  KeSicActivity(
      "422160",
      "Construction of pumping stations and power plants",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42216 · Construction of pumping stations and power plants",
  ),
  KeSicActivity(
      "422170",
      "Water well drilling except boreholes",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42217 · Water well drilling except boreholes",
  ),
  KeSicActivity(
      "422190",
      "Construction of other utility projects",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4221 · Construction of utility projects(except borehole drilling) / Subclass 42219 · Construction of other utility projects",
  ),
  KeSicActivity(
      "422210",
      "Borehole drilling",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4222 · Borehole drilling and Equipping / Subclass 42221 · Borehole drilling",
  ),
  KeSicActivity(
      "422220",
      "Borehole equipping",
      "Section F · Construction / Division 42 · C Civil engineering / Group 422 · Construction of utility projects / Class 4222 · Borehole drilling and Equipping / Subclass 42222 · Borehole equipping",
  ),
  KeSicActivity(
      "429010",
      "Construction of industrial facilities, except buildings,",
      "Section F · Construction / Division 42 · C Civil engineering / Group 429 · Construction of other civil engineering projects / Class 4290 · Construction of other civil engineering projects / Subclass 42901 · Construction of industrial facilities, except buildings,",
  ),
  KeSicActivity(
      "429020",
      "Construction of dams and dykes, waterways, harbour and river works, pleasure ports (marinas), locks, etc",
      "Section F · Construction / Division 42 · C Civil engineering / Group 429 · Construction of other civil engineering projects / Class 4290 · Construction of other civil engineering projects / Subclass 42902 · Construction of dams and dykes, waterways, harbour and river works, pleasure ports (marinas), locks, etc",
  ),
  KeSicActivity(
      "429030",
      "Dredging of waterways",
      "Section F · Construction / Division 42 · C Civil engineering / Group 429 · Construction of other civil engineering projects / Class 4290 · Construction of other civil engineering projects / Subclass 42903 · Dredging of waterways",
  ),
  KeSicActivity(
      "429040",
      "Construction work, other than buildings such as outdoor sports facilities",
      "Section F · Construction / Division 42 · C Civil engineering / Group 429 · Construction of other civil engineering projects / Class 4290 · Construction of other civil engineering projects / Subclass 42904 · Construction work, other than buildings such as outdoor sports facilities",
  ),
  KeSicActivity(
      "429050",
      "Land subdivision with land improvement (e.g. adding of roads, utility infrastructure)",
      "Section F · Construction / Division 42 · C Civil engineering / Group 429 · Construction of other civil engineering projects / Class 4290 · Construction of other civil engineering projects / Subclass 42905 · Land subdivision with land improvement (e.g. adding of roads, utility infrastructure)",
  ),
  KeSicActivity(
      "431100",
      "Demolition or wrecking of buildings and other structures",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 431 · Demolition and site preparation / Class 4311 · Demolition / Subclass 43110 · Demolition or wrecking of buildings and other structures",
  ),
  KeSicActivity(
      "431210",
      "Clearing of building sites, earth moving: excavation, landfill, levelling and grading of construction sites, trench",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 431 · Demolition and site preparation / Class 4312 · Site preparation / Subclass 43121 · Clearing of building sites, earth moving: excavation, landfill, levelling and grading of construction sites, trench",
  ),
  KeSicActivity(
      "431220",
      "Drilling, boring and core sampling for construction, geophysical, geological or similar purposes",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 431 · Demolition and site preparation / Class 4312 · Site preparation / Subclass 43122 · Drilling, boring and core sampling for construction, geophysical, geological or similar purposes",
  ),
  KeSicActivity(
      "431230",
      "Site preparation for mining(except for oil and gas sites)",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 431 · Demolition and site preparation / Class 4312 · Site preparation / Subclass 43123 · Site preparation for mining(except for oil and gas sites)",
  ),
  KeSicActivity(
      "431240",
      "Building site drainage excluding utility facilities",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 431 · Demolition and site preparation / Class 4312 · Site preparation / Subclass 43124 · Building site drainage excluding utility facilities",
  ),
  KeSicActivity(
      "431290",
      "Other site preparation activities",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 431 · Demolition and site preparation / Class 4312 · Site preparation / Subclass 43129 · Other site preparation activities",
  ),
  KeSicActivity(
      "432111",
      "Structured cabling and IP telephony installationincludingAudioVisualsystems e.g. Conference systems, Public Address, Video Conference systems, Data/Voice cabling, Network equipment, IP telephony, Fibre optic installations Building management systems",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4321 · Electrical installation / Subclass 43211 · Installation of electrical systems",
  ),
  KeSicActivity(
      "432113",
      "Instrumentation and PLC systems including Security and Access Control systems e.g. CCTV surveillance system, Access control, Alarm systems, parking management system e.g. Electronic Control Systems, Digital Display systems, Programmable Logic control (PLC) Systems",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4321 · Electrical installation / Subclass 43211 · Installation of electrical systems",
  ),
  KeSicActivity(
      "432119",
      "Other Installation of electrical systems",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4321 · Electrical installation / Subclass 43211 · Installation of electrical systems",
  ),
  KeSicActivity(
      "432120",
      "Connecting of electric appliances and household equipment, including baseboard heating",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4321 · Electrical installation / Subclass 43212 · Connecting of electric appliances and household equipment, including baseboard heating",
  ),
  KeSicActivity(
      "432130",
      "Installation and Maintenance of Generators",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4321 · Electrical installation / Subclass 43213 · Installation and Maintenance of Generators",
  ),
  KeSicActivity(
      "432140",
      "Installation of wireless communication system e.g. GSM, TDMA/CDMA 83 suppression systems, radio communications, broadcast equipment",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4321 · Electrical installation / Subclass 43214 · Installation of wireless communication system",
  ),
  KeSicActivity(
      "432210",
      "Plumbing, heating and air-conditioning systems installation in buildings or other construction projects",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4322 · Plumbing, heat and air-conditioning installation / Subclass 43221 · Plumbing, heating and air-conditioning systems installation in buildings or other construction projects",
  ),
  KeSicActivity(
      "432211",
      "Plumbing and sanitary equipment, Domestic water storage",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4322 · Plumbing, heat and air-conditioning installation / Subclass 43221 · Plumbing, heating and air-conditioning systems installation in buildings or other construction projects",
  ),
  KeSicActivity(
      "432212",
      "Boilers, Incinerators ,Compressed air, hydraulic liquidified petroleum and medical gas installation, gas pipe handling, gas reticulation, air conditioning",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4322 · Plumbing, heat and air-conditioning installation / Subclass 43221 · Plumbing, heating and air-conditioning systems installation in buildings or other construction projects",
  ),
  KeSicActivity(
      "432213",
      "Installation of Automatic fire suppression system",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4322 · Plumbing, heat and air-conditioning installation / Subclass 43221 · Plumbing, heating and air-conditioning systems installation in buildings or other construction projects",
  ),
  KeSicActivity(
      "432219",
      "Other plumbing, heating and air- conditioning systems installation in buildings or other construction projects",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4322 · Plumbing, heat and air-conditioning installation / Subclass 43221 · Plumbing, heating and air-conditioning systems installation in buildings or other construction projects",
  ),
  KeSicActivity(
      "432220",
      "Duct work installation",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4322 · Plumbing, heat and air-conditioning installation / Subclass 43222 · Duct work installation",
  ),
  KeSicActivity(
      "432911",
      "Installation and maintenance of elevators, escalators, Skywalks, Lift hoists, mechanical ramps, travelators, conveyors and belt ins",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4329 · Other construction installation / Subclass 43291 · Other construction installation in buildings",
  ),
  KeSicActivity(
      "432919",
      "Other construction installation in buildings",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4329 · Other construction installation / Subclass 43291 · Other construction installation in buildings",
  ),
  KeSicActivity(
      "432921",
      "Construction, installation and testing of gas/petrol stations oil/gas reticulation, oil/gas storage tanks",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4329 · Other construction installation / Subclass 43292 · Installation in other construction projects",
  ),
  KeSicActivity(
      "432929",
      "Installation in other construction projects",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 432 · Electrical, plumbing and other construction installation activities / Class 4329 · Other construction installation / Subclass 43292 · Installation in other construction projects",
  ),
  KeSicActivity(
      "433100",
      "Interior and exterior painting of buildings and Other civil engineering structures",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4331 · Painters / Subclass 43310 · Interior and exterior painting of buildings and other civil engineering structures",
  ),
  KeSicActivity(
      "433910",
      "Application in buildings or other construction projects of interior and exterior plaster or stucco, including related lathing materials",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43391 · Application in buildings or other construction projects of interior and exterior plaster or stucco, including related lathing materials",
  ),
  KeSicActivity(
      "433920",
      "Installation of doors (except automated and revolving), windows, door and window frames, of wood or other materials",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43392 · Installation of doors (except automated and revolving), windows, door and window frames, of wood or other materials",
  ),
  KeSicActivity(
      "433931",
      "Installation of furniture, fitted kitchens, staircases, shop fittings and the like",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43393 · Installation of furniture, fitted kitchens, staircases, shop fittings and the like",
  ),
  KeSicActivity(
      "433932",
      "Glazing( Installation of glass mirrors including structural glass etc)",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43393 · Installation of furniture, fitted kitchens, staircases, shop fittings and the like",
  ),
  KeSicActivity(
      "433941",
      "Interior completion – gypsums",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43394 · Interior completion such as ceilings, gypsums, wooden wall coverings, movable partitions, etc",
  ),
  KeSicActivity(
      "433942",
      "Other interior completion such as ceilings, wooden wall coverings, movable partitions, etc",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43394 · Interior completion such as ceilings, gypsums, wooden wall coverings, movable partitions, etc",
  ),
  KeSicActivity(
      "433951",
      "Ceramic, concrete or cut stone wall or floor tiles, ceramic stove fitting",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43395 · Laying, tiling, hanging or fitting in buildings or other construction projects",
  ),
  KeSicActivity(
      "433952",
      "Parquet and other wooden floor coverings",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43395 · Laying, tiling, hanging or fitting in buildings or other construction projects",
  ),
  KeSicActivity(
      "433953",
      "Carpets and linoleum floor coverings, including of rubber or plastic",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43395 · Laying, tiling, hanging or fitting in buildings or other construction projects",
  ),
  KeSicActivity(
      "433954",
      "Terrazzo floor or wall coverings",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43395 · Laying, tiling, hanging or fitting in buildings or other construction projects",
  ),
  KeSicActivity(
      "433955",
      "Marble, granite or slate floor or wall coverings",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43395 · Laying, tiling, hanging or fitting in buildings or other construction projects",
  ),
  KeSicActivity(
      "433959",
      "Other laying, tiling, hanging or fitting in buildings or other construction projects",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43395 · Laying, tiling, hanging or fitting in buildings or other construction projects",
  ),
  KeSicActivity(
      "433960",
      "Cleaning of new buildings after construction",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43396 · Cleaning of new buildings after construction",
  ),
  KeSicActivity(
      "433970",
      "Interior installation of shops, mobile homes, boats etc",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43397 · Interior installation of shops, mobile homes, boats etc",
  ),
  KeSicActivity(
      "433990",
      "Other building completion work n.e.c",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 433 · Building completion and finishing / Class 4339 · Other Building completion and finishing / Subclass 43399 · Other building completion work n.e.c",
  ),
  KeSicActivity(
      "439100",
      "Structural steel erectors",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 439 · Other specialized construction activities / Class 4391 · Structural steel erectors / Subclass 43910 · Structural steel erectors",
  ),
  KeSicActivity(
      "439200",
      "Roof covering for residential buildings and minor repairs",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 439 · Other specialized construction activities / Class 4392 · Roof-tilers and minor repairs / Subclass 43920 · Roof-tilers and minor repairs",
  ),
  KeSicActivity(
      "439910",
      "Other construction activities specializing in one aspect common to different kind of structures, requiring specialized skill or equipment",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 439 · Other specialized construction activities / Class 4399 · Other specialized construction activities / Subclass 43991 · Construction activities specializing in one aspect common to different kind of",
  ),
  KeSicActivity(
      "439920",
      "Construction of outdoor swimming pools",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 439 · Other specialized construction activities / Class 4399 · Other specialized construction activities / Subclass 43992 · Construction of outdoor swimming pools",
  ),
  KeSicActivity(
      "439930",
      "Steam cleaning, sand blasting and similar activities for building exteriors",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 439 · Other specialized construction activities / Class 4399 · Other specialized construction activities / Subclass 43993 · Steam cleaning, sand blasting and similar activities for building exteriors",
  ),
  KeSicActivity(
      "439940",
      "Renting of cranes with operator and other construction equipment",
      "Section F · Construction / Division 43 · Specialized construction activities / Group 439 · Other specialized construction activities / Class 4399 · Other specialized construction activities / Subclass 43994 · Renting of cranes with operator and other construction equipment",
  ),
  KeSicActivity(
      "451010",
      "Sale of new motor vehicles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 45 · Wholesale and retail trade and repair of motor vehicles and motorcycles / Group 451 · Sale of motor vehicles / Class 4510 · Sale of motor vehicles / Subclass 45101 · Sale of new motor vehicles",
  ),
  KeSicActivity(
      "451020",
      "sale of used motor vehicles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 45 · Wholesale and retail trade and repair of motor vehicles and motorcycles / Group 451 · Sale of motor vehicles / Class 4510 · Sale of motor vehicles / Subclass 45102 · sale of used motor vehicles",
  ),
  KeSicActivity(
      "452000",
      "Maintenance and repair of motor vehicles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 45 · Wholesale and retail trade and repair of motor vehicles and motorcycles / Group 452 · Maintenance and repair of motor vehicles / Class 4520 · Maintenance and repair of motor vehicles / Subclass 45200 · Maintenance and repair of motor vehicles",
  ),
  KeSicActivity(
      "453000",
      "Sale of motor vehicle parts and accessories",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 45 · Wholesale and retail trade and repair of motor vehicles and motorcycles / Group 453 · Sale of motor vehicle parts and accessories / Class 4530 · Sale of motor vehicle parts and accessories / Subclass 45300 · Sale of motor vehicle parts and accessories",
  ),
  KeSicActivity(
      "454010",
      "Sale of motorcycles and related parts and accessories",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 45 · Wholesale and retail trade and repair of motor vehicles and motorcycles / Group 454 · Sale, maintenance and repair of motorcycles and related parts and accessories / Class 4540 · Sale, maintenance and repair of motorcycles and related parts and accessories / Subclass 45401 · Sale of motorcycles and related parts and accessories",
  ),
  KeSicActivity(
      "454020",
      "maintenance and repair of motorcycles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 45 · Wholesale and retail trade and repair of motor vehicles and motorcycles / Group 454 · Sale, maintenance and repair of motorcycles and related parts and accessories / Class 4540 · Sale, maintenance and repair of motorcycles and related parts and accessories / Subclass 45402 · maintenance and repair of motorcycles",
  ),
  KeSicActivity(
      "461000",
      "Wholesale on a fee or contract basis",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 461 · Wholesale on a fee or contract basis / Class 4610 · Wholesale on a fee or contract basis / Subclass 46100 · Wholesale on a fee or contract basis",
  ),
  KeSicActivity(
      "462001",
      "Wholesale of agricultural raw materials",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 462 · Wholesale of agricultural raw materials and live animals / Class 4620 · Wholesale of agricultural raw materials and live animals / Subclass 46200 · Wholesale of agricultural raw materials and live animals",
  ),
  KeSicActivity(
      "462002",
      "Wholesale of live animals",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 462 · Wholesale of agricultural raw materials and live animals / Class 4620 · Wholesale of agricultural raw materials and live animals / Subclass 46200 · Wholesale of agricultural raw materials and live animals",
  ),
  KeSicActivity(
      "463011",
      "Wholesale of tea",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46301 · Wholesale of food",
  ),
  KeSicActivity(
      "463012",
      "Wholesale of coffee",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46301 · Wholesale of food",
  ),
  KeSicActivity(
      "463013",
      "Wholesale of dairy products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46301 · Wholesale of food",
  ),
  KeSicActivity(
      "463014",
      "Wholesale of eggs and egg products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46301 · Wholesale of food",
  ),
  KeSicActivity(
      "463015",
      "Wholesale of meat and meat products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46301 · Wholesale of food",
  ),
  KeSicActivity(
      "463019",
      "Other Wholesale of food products n.e.c",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46301 · Wholesale of food",
  ),
  KeSicActivity(
      "463021",
      "Wholesale of beer",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46302 · Wholesale of alcoholic beverages",
  ),
  KeSicActivity(
      "463022",
      "Wholesale of wines and spirits",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46302 · Wholesale of alcoholic beverages",
  ),
  KeSicActivity(
      "463031",
      "Wholesale of natural mineral water and other bottled water",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46303 · Wholesale of non-alcoholic beverages",
  ),
  KeSicActivity(
      "463032",
      "Wholesale of soft drinks",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46303 · Wholesale of non-alcoholic beverages",
  ),
  KeSicActivity(
      "463040",
      "Wholesale of tobacco products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46304 · Wholesale of tobacco products",
  ),
  KeSicActivity(
      "463050",
      "Wholesale of Khat(miraa) and related products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 463 · Wholesale of food, beverages and tobacco / Class 4630 · Wholesale of food, beverages and tobacco / Subclass 46305 · Wholesale of Khat(miraa) and related products",
  ),
  KeSicActivity(
      "464101",
      "Wholesale of textiles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4641 · Wholesale of textiles, clothing and footwear / Subclass 46410 · Wholesale of textiles, clothing and footwear",
  ),
  KeSicActivity(
      "464102",
      "Wholesale of clothing",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4641 · Wholesale of textiles, clothing and footwear / Subclass 46410 · Wholesale of textiles, clothing and footwear",
  ),
  KeSicActivity(
      "464103",
      "Wholesale of footwear",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4641 · Wholesale of textiles, clothing and footwear / Subclass 46410 · Wholesale of textiles, clothing and footwear",
  ),
  KeSicActivity(
      "464200",
      "Wholesale of second hand textiles, clothing and footwear",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4642 · Wholesale of second hand textiles, clothing and footwear / Subclass 46420 · Wholesale of second hand textiles, clothing and footwear",
  ),
  KeSicActivity(
      "464910",
      "Wholesale of household furniture",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4649 · Wholesale of other household goods / Subclass 46491 · Wholesale of household furniture",
  ),
  KeSicActivity(
      "464920",
      "Wholesale of lighting equipment, household appliances and consumer electronics",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4649 · Wholesale of other household goods / Subclass 46492 · Wholesale of lighting equipment, household appliances and consumer electronics",
  ),
  KeSicActivity(
      "464930",
      "Wholesale of cutlery, china and glassware, woodenware, wickerwork and cork ware etc",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4649 · Wholesale of other household goods / Subclass 46493 · Wholesale of cutlery, china and glassware, woodenware, wickerwork and cork ware etc",
  ),
  KeSicActivity(
      "464940",
      "Wholesale of pharmaceutical and medical goods",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4649 · Wholesale of other household goods / Subclass 46494 · Wholesale of pharmaceutical and medical goods",
  ),
  KeSicActivity(
      "464950",
      "Wholesale of perfumeries, cosmetics and soaps",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4649 · Wholesale of other household goods / Subclass 46495 · Wholesale of perfumeries, cosmetics and soaps",
  ),
  KeSicActivity(
      "464960",
      "Wholesale of stationery, books, magazines and newspapers",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4649 · Wholesale of other household goods / Subclass 46496 · Wholesale of stationery, books, magazines and newspapers",
  ),
  KeSicActivity(
      "464990",
      "Wholesale of other household goods n.e.c",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 464 · Wholesale of household goods / Class 4649 · Wholesale of other household goods / Subclass 46499 · Wholesale of other household goods n.e.c",
  ),
  KeSicActivity(
      "465100",
      "Wholesale of computers, computer peripheral equipment and software",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 465 · Wholesale of machinery, equipment and supplies / Class 4651 · Wholesale of computers, computer peripheral equipment and software / Subclass 46510 · Wholesale of computers, computer peripheral equipment and software",
  ),
  KeSicActivity(
      "465200",
      "Wholesale of electronic and telecommunications equipment and parts",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 465 · Wholesale of machinery, equipment and supplies / Class 4652 · Wholesale of electronic and telecommunications equipment and parts / Subclass 46520 · Wholesale of electronic and telecommunications equipment and parts",
  ),
  KeSicActivity(
      "465300",
      "Wholesale of agricultural machinery, equipment and supplies",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 465 · Wholesale of machinery, equipment and supplies / Class 4653 · Wholesale of agricultural machinery, equipment and supplies / Subclass 46530 · Wholesale of agricultural machinery, equipment and supplies",
  ),
  KeSicActivity(
      "465900",
      "Wholesale of other machinery and equipment",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 465 · Wholesale of machinery, equipment and supplies / Class 4659 · Wholesale of other machinery and equipment / Subclass 46590 · Wholesale of other machinery and equipment",
  ),
  KeSicActivity(
      "466100",
      "Wholesale of solid, liquid and gaseous fuels and related products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4661 · Wholesale of solid, liquid and gaseous fuels and related products / Subclass 46610 · Wholesale of solid, liquid and gaseous fuels and related products",
  ),
  KeSicActivity(
      "466200",
      "Wholesale of metals and metal ores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4662 · Wholesale of metals and metal ores / Subclass 46620 · Wholesale of metals and metal ores",
  ),
  KeSicActivity(
      "466301",
      "Wholesale of wood and wood products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466302",
      "Wholesale of paint and varnish",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466303",
      "Wholesale of construction(sand and gravel) materials",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466304",
      "Wholesale of wallpaper ,floor coverings, fitting and fixtures",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466305",
      "Wholesale of glass",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466306",
      "Wholesale of hardware , locks and tools such as hammers, saws, screwdrivers and other hand tools",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466307",
      "Wholesale of electrical equipment and fittings",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466308",
      "Wholesale of sanitary and sanitary installation equipment",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466309",
      "Other Wholesale of construction materials, hardware, plumbing and heating equipment and supplies n.e.c",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4663 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies / Subclass 46630 · Wholesale of construction materials, hardware, plumbing and heating equipment and supplies",
  ),
  KeSicActivity(
      "466901",
      "Wholesale of industrial chemicals",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4669 · Wholesale of waste and scrap and other products n.e.c / Subclass 46690 · Wholesale of waste and scrap and other products n.e.c",
  ),
  KeSicActivity(
      "466902",
      "Wholesale of fertilizers and agrochemical products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4669 · Wholesale of waste and scrap and other products n.e.c / Subclass 46690 · Wholesale of waste and scrap and other products n.e.c",
  ),
  KeSicActivity(
      "466903",
      "Wholesale of non-metallic products except cement, sand and gravel",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4669 · Wholesale of waste and scrap and other products n.e.c / Subclass 46690 · Wholesale of waste and scrap and other products n.e.c",
  ),
  KeSicActivity(
      "466904",
      "Wholesale of scrap metals waste and junk",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4669 · Wholesale of waste and scrap and other products n.e.c / Subclass 46690 · Wholesale of waste and scrap and other products n.e.c",
  ),
  KeSicActivity(
      "466905",
      "Wholesale of scrap except metals",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4669 · Wholesale of waste and scrap and other products n.e.c / Subclass 46690 · Wholesale of waste and scrap and other products n.e.c",
  ),
  KeSicActivity(
      "466909",
      "Wholesale of other waste and scrap and products n.e.c",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 466 · Other specialized wholesale / Class 4669 · Wholesale of waste and scrap and other products n.e.c / Subclass 46690 · Wholesale of waste and scrap and other products n.e.c",
  ),
  KeSicActivity(
      "469000",
      "Non-specialized wholesale trade",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 46 · Wholesale trade, except of motor vehicles and motorcycles / Group 469 · Non-specialized wholesale trade / Class 4690 · Non-specialized wholesale trade / Subclass 46900 · Non-specialized wholesale trade",
  ),
  KeSicActivity(
      "471110",
      "Retailsaleinnon-specialized self-selection stores with food, beverages or tobacco predominating",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 471 · Retail sale in non-specialized stores / Class 4711 · Retail sale in non-specialized stores with food, beverages or tobacco predominating / Subclass 47111 · Retailsaleinnon-specialized self-selection stores with food, beverages or tobacco predominating",
  ),
  KeSicActivity(
      "471190",
      "Retail sale in other non-specialized stores with food, beverages or tobacco predominating",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 471 · Retail sale in non-specialized stores / Class 4711 · Retail sale in non-specialized stores with food, beverages or tobacco predominating / Subclass 47119 · Retail sale in other non-specialized stores with food, beverages or tobacco predominating",
  ),
  KeSicActivity(
      "471910",
      "Retailsaleinnon-specialized self-selection stores where food, beverages or tobacco is not predominating",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 471 · Retail sale in non-specialized stores / Class 4719 · Other retail sale in non-specialized stores / Subclass 47191 · Retailsaleinnon-specialized self-selection stores where food, beverages or tobacco is not predominating",
  ),
  KeSicActivity(
      "471990",
      "Retail sale in other non-specialized stores where food, beverages or tobacco is not predominating",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 471 · Retail sale in non-specialized stores / Class 4719 · Other retail sale in non-specialized stores / Subclass 47199 · Retail sale in other non-specialized stores where food, beverages or tobacco is not predominating",
  ),
  KeSicActivity(
      "472110",
      "Fresh or preserved fruit and vegetables (groceries)",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 472 · Retail sale of food, beverages and tobacco in specialized stores / Class 4721 · Retail sale of food in specialized stores / Subclass 47211 · Fresh or preserved fruit and vegetables (groceries)",
  ),
  KeSicActivity(
      "472120",
      "Dairy Products and eggs",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 472 · Retail sale of food, beverages and tobacco in specialized stores / Class 4721 · Retail sale of food in specialized stores / Subclass 47212 · Dairy Products and eggs",
  ),
  KeSicActivity(
      "472130",
      "Meat and Meat products ( including Poultry, fish, other seafoods and products thereof)",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 472 · Retail sale of food, beverages and tobacco in specialized stores / Class 4721 · Retail sale of food in specialized stores / Subclass 47213 · Meat and Meat products ( including Poultry, fish, other seafoods and products thereof)",
  ),
  KeSicActivity(
      "472140",
      "Bakery Products and Sugar confectionary",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 472 · Retail sale of food, beverages and tobacco in specialized stores / Class 4721 · Retail sale of food in specialized stores / Subclass 47214 · Bakery Products and Sugar confectionary",
  ),
  KeSicActivity(
      "472190",
      "other food products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 472 · Retail sale of food, beverages and tobacco in specialized stores / Class 4721 · Retail sale of food in specialized stores / Subclass 47219 · Other food products",
  ),
  KeSicActivity(
      "472210",
      "Retail sale in Liquor stores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 472 · Retail sale of food, beverages and tobacco in specialized stores / Class 4722 · Retail sale of beverages in specialized stores / Subclass 47221 · Retail sale in Liquor stores",
  ),
  KeSicActivity(
      "472220",
      "Retail sale of non-alcoholic beverages in specialised stores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 472 · Retail sale of food, beverages and tobacco in specialized stores / Class 4722 · Retail sale of beverages in specialized stores / Subclass 47222 · Retail sale of non-alcoholic beverages in specialised stores",
  ),
  KeSicActivity(
      "472300",
      "Retail sale of tobacco products in specialized stores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 472 · Retail sale of food, beverages and tobacco in specialized stores / Class 4723 · Retail sale of tobacco products in specialized stores / Subclass 47230 · Retail sale of tobacco products in specialized stores",
  ),
  KeSicActivity(
      "473010",
      "Retail sale of fuel for motor vehicles and motorcycles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 473 · Retail sale of automotive fuel in specialized stores / Class 4730 · Retail sale of automotive fuel in specialized stores / Subclass 47301 · Retail sale of fuel for motor vehicles and motorcycles",
  ),
  KeSicActivity(
      "473020",
      "Retail sale of lubricating products and cooling products for motor vehicles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 473 · Retail sale of automotive fuel in specialized stores / Class 4730 · Retail sale of automotive fuel in specialized stores / Subclass 47302 · Retail sale of lubricating products and cooling products for motor vehicles",
  ),
  KeSicActivity(
      "474110",
      "Retail sale of computers, computer peripheral equipment, video game consoles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 474 · Retail sale of information and communications equipment in specialized stores / Class 4741 · Retail sale of computers, peripheral units, software and telecommunications equipment in specialized stores / Subclass 47411 · Retail sale of computers, computer peripheral equipment, video game consoles",
  ),
  KeSicActivity(
      "474120",
      "Retail sale of cellular phones , parts and accessories",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 474 · Retail sale of information and communications equipment in specialized stores / Class 4741 · Retail sale of computers, peripheral units, software and telecommunications equipment in specialized stores / Subclass 47412 · Retail sale of cellular phones , parts and accessories",
  ),
  KeSicActivity(
      "474130",
      "Retail sale of non-customized software, including video games",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 474 · Retail sale of information and communications equipment in specialized stores / Class 4741 · Retail sale of computers, peripheral units, software and telecommunications equipment in specialized stores / Subclass 47413 · Retail sale of non-customized software, including video games",
  ),
  KeSicActivity(
      "474140",
      "Retail sale of other telecommunication equipment",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 474 · Retail sale of information and communications equipment in specialized stores / Class 4741 · Retail sale of computers, peripheral units, software and telecommunications equipment in specialized stores / Subclass 47414 · Retail sale of other telecommunication equipment",
  ),
  KeSicActivity(
      "474200",
      "Retail sale of audio and video equipment in specialized stores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 474 · Retail sale of information and communications equipment in specialized stores / Class 4742 · Retail sale of audio and video equipment in specialized stores / Subclass 47420 · Retail sale of audio and video equipment in specialized stores",
  ),
  KeSicActivity(
      "475110",
      "Retail sale of fabrics and textiles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4751 · Retail sale of textiles in specialized stores / Subclass 47511 · Retail sale of fabrics and textiles",
  ),
  KeSicActivity(
      "475120",
      "Retail sale of knitting yarn",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4751 · Retail sale of textiles in specialized stores / Subclass 47512 · Retail sale of knitting yarn",
  ),
  KeSicActivity(
      "475130",
      "Retail sale of haberdashery, basic materials for rug, tapestry or embroidery making",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4751 · Retail sale of textiles in specialized stores / Subclass 47513 · Retail sale of haberdashery, basic materials for rug, tapestry or embroidery making",
  ),
  KeSicActivity(
      "475210",
      "Retail sale of general hardware",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4752 · Retail sale of hardware, paints and glass in specialized stores / Subclass 47521 · Retail sale of general hardware",
  ),
  KeSicActivity(
      "475220",
      "Retail sale of paints, varnishes and lacquers",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4752 · Retail sale of hardware, paints and glass in specialized stores / Subclass 47522 · Retail sale of paints, varnishes and lacquers",
  ),
  KeSicActivity(
      "475230",
      "Retail sale of flat glass",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4752 · Retail sale of hardware, paints and glass in specialized stores / Subclass 47523 · Retail sale of flat glass",
  ),
  KeSicActivity(
      "475240",
      "Retail sale of other building material such as bricks, wood, sanitary equipment",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4752 · Retail sale of hardware, paints and glass in specialized stores / Subclass 47524 · Retail sale of other building material such as bricks, wood, sanitary equipment",
  ),
  KeSicActivity(
      "475310",
      "Retail sale of carpets and rugs",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4753 · Retail sale of carpets, rugs, wall and floor coverings in specialized stores / Subclass 47531 · Retail sale of carpets and rugs",
  ),
  KeSicActivity(
      "475320",
      "Retail sale of curtains and net curtains",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4753 · Retail sale of carpets, rugs, wall and floor coverings in specialized stores / Subclass 47532 · Retail sale of curtains and net curtains",
  ),
  KeSicActivity(
      "475330",
      "Retail sale of wallpaper and floor coverings",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4753 · Retail sale of carpets, rugs, wall and floor coverings in specialized stores / Subclass 47533 · Retail sale of wallpaper and floor coverings",
  ),
  KeSicActivity(
      "475390",
      "Other Retail sale of carpets, rugs, wall and floor coverings in specialized stores n.e.c",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4753 · Retail sale of carpets, rugs, wall and floor coverings in specialized stores / Subclass 47539 · Other Retail sale of carpets, rugs, wall and floor coverings in specialized stores n.e.c",
  ),
  KeSicActivity(
      "475400",
      "Retail sale of small agricultural machinery, equipment and supplies",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4754 · Retail sale of small agricultural machinery, equipment and supplies / Subclass 47540 · Retail sale of small agricultural machinery, equipment and supplies",
  ),
  KeSicActivity(
      "475910",
      "Retail sale of household furniture including wooden, cork and wickerwork goods",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4759 · Retail sale of electrical household appliances, furniture, lighting equipment and other household articles in specialized stores / Subclass 47591 · Retail sale of household furniture including wooden, cork and wickerwork goods",
  ),
  KeSicActivity(
      "475920",
      "Retail sale of articles for lighting",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4759 · Retail sale of electrical household appliances, furniture, lighting equipment and other household articles in specialized stores / Subclass 47592 · Retail sale of articles for lighting",
  ),
  KeSicActivity(
      "475930",
      "Retail sale of household utensils and cutlery, crockery, glassware, china and pottery",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4759 · Retail sale of electrical household appliances, furniture, lighting equipment and other household articles in specialized stores / Subclass 47593 · Retail sale of household utensils and cutlery, crockery, glassware, china and pottery",
  ),
  KeSicActivity(
      "475940",
      "Retail sale of musical instruments and scores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4759 · Retail sale of electrical household appliances, furniture, lighting equipment and other household articles in specialized stores / Subclass 47594 · Retail sale of musical instruments and scores",
  ),
  KeSicActivity(
      "475950",
      "Retail sale of security systems, such as locking devices, safes, and vaults, without installation or maintenance services",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4759 · Retail sale of electrical household appliances, furniture, lighting equipment and other household articles in specialized stores / Subclass 47595 · Retail sale of security systems, such as locking devices, safes, and vaults, without installation or maintenance services",
  ),
  KeSicActivity(
      "475990",
      "Retail sale of household articles and equipment n.e.c",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 475 · Retail sale of other household equipment in specialized stores / Class 4759 · Retail sale of electrical household appliances, furniture, lighting equipment and other household articles in specialized stores / Subclass 47599 · Retail sale of household articles and equipment n.e.c",
  ),
  KeSicActivity(
      "476110",
      "Retail sale of stationery, office supplies and books of all kinds",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 476 · Retail sale of cultural and recreation goods in specialized stores / Class 4761 · Retail sale of books, newspapers and stationary in specialized stores / Subclass 47611 · Retail sale of stationery, office supplies and books of all kinds",
  ),
  KeSicActivity(
      "476120",
      "Retail sale of newspapers and magazines",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 476 · Retail sale of cultural and recreation goods in specialized stores / Class 4761 · Retail sale of books, newspapers and stationary in specialized stores / Subclass 47612 · Retail sale of newspapers and magazines",
  ),
  KeSicActivity(
      "476200",
      "Retail sale of music and video recordings in specialized stores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 476 · Retail sale of cultural and recreation goods in specialized stores / Class 4762 · Retail sale of music and video recordings in specialized stores / Subclass 47620 · Retail sale of music and video recordings in specialized stores",
  ),
  KeSicActivity(
      "476300",
      "Retail sale of sporting equipment in specialized stores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 476 · Retail sale of cultural and recreation goods in specialized stores / Class 4763 · Retail sale of sporting equipment in specialized stores / Subclass 47630 · Retail sale of sporting equipment in specialized stores",
  ),
  KeSicActivity(
      "476400",
      "Retail sale of games and toys in specialized stores",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 476 · Retail sale of cultural and recreation goods in specialized stores / Class 4764 · Retail sale of games and toys in specialized stores / Subclass 47640 · Retail sale of games and toys in specialized stores",
  ),
  KeSicActivity(
      "477110",
      "Retail sale of articles of clothing",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4771 · Retail sale of clothing, footwear and leather articles in specialized stores / Subclass 47711 · Retail sale of articles of clothing",
  ),
  KeSicActivity(
      "477120",
      "Retail sale of footwear and leather goods",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4771 · Retail sale of clothing, footwear and leather articles in specialized stores / Subclass 47712 · Retail sale of footwear and leather goods",
  ),
  KeSicActivity(
      "477190",
      "other retail sale of clothing, footwear and leather articles in specialized stores n.e.c",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4771 · Retail sale of clothing, footwear and leather articles in specialized stores / Subclass 47719 · other retail sale of clothing, footwear and leather articles in specialized stores n.e.c",
  ),
  KeSicActivity(
      "477210",
      "Retail sale of pharmaceuticals",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4772 · Retail sale of pharmaceutical and medical goods, cosmetic and toilet articles in specialized stores / Subclass 47721 · Retail sale of pharmaceuticals",
  ),
  KeSicActivity(
      "477220",
      "Retail sale of medical and orthopaedic goods",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4772 · Retail sale of pharmaceutical and medical goods, cosmetic and toilet articles in specialized stores / Subclass 47722 · Retail sale of medical and orthopaedic goods",
  ),
  KeSicActivity(
      "477230",
      "Retail sale of perfumery and cosmetic articles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4772 · Retail sale of pharmaceutical and medical goods, cosmetic and toilet articles in specialized stores / Subclass 47723 · Retail sale of perfumery and cosmetic articles",
  ),
  KeSicActivity(
      "477310",
      "Retail sale of photographic, optical and precision equipment",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47731 · Retail sale of photographic, optical and precision equipment",
  ),
  KeSicActivity(
      "477320",
      "Activities of opticians",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47732 · Activities of opticians",
  ),
  KeSicActivity(
      "477330",
      "Retail sale of watches, clocks and jewellery",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47733 · Retail sale of watches, clocks and jewellery",
  ),
  KeSicActivity(
      "477341",
      "Retail sale of flowers, plants",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47734 · Retail sale of flowers, plants, seeds, fertilizers, pet animals and pet food",
  ),
  KeSicActivity(
      "477342",
      "Retail sale of seeds, fertilizers and pet food",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47734 · Retail sale of flowers, plants, seeds, fertilizers, pet animals and pet food",
  ),
  KeSicActivity(
      "477343",
      "Retail sale of pet animals",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47734 · Retail sale of flowers, plants, seeds, fertilizers, pet animals and pet food",
  ),
  KeSicActivity(
      "477351",
      "Retail sale of kerosene",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47735 · Retail sale of household fuel oil, bottled gas, coal and fuel wood",
  ),
  KeSicActivity(
      "477352",
      "Retail sale of liquefied petroleum gas(lpg)",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47735 · Retail sale of household fuel oil, bottled gas, coal and fuel wood",
  ),
  KeSicActivity(
      "477353",
      "Retail sale of charcoal and fuel wood",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47735 · Retail sale of household fuel oil, bottled gas, coal and fuel wood",
  ),
  KeSicActivity(
      "477359",
      "Other retail sale of household fuel oil, bottled gas, coal and fuel wood",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47735 · Retail sale of household fuel oil, bottled gas, coal and fuel wood",
  ),
  KeSicActivity(
      "477360",
      "Retail sale of souvenirs, craftwork and religious articles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47736 · Retail sale of souvenirs, craftwork and religious articles",
  ),
  KeSicActivity(
      "477370",
      "Retail sale of cleaning materials",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47737 · Retail sale of cleaning materials",
  ),
  KeSicActivity(
      "477380",
      "Activities of commercial art galleries",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47738 · Activities of commercial art galleries",
  ),
  KeSicActivity(
      "477390",
      "Retail sale of non-food products n.e.c",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4773 · Other retail sale of new goods in specialized stores / Subclass 47739 · Retail sale of non-food products n.e.c",
  ),
  KeSicActivity(
      "477400",
      "Retailsaleofsecond-handgoodsexcluding motor vehicles",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 477 · Retail sale of other goods in specialized stores / Class 4774 · Retail sale of second-hand goods / Subclass 47740 · Retailsaleofsecond-handgoodsexcluding motor vehicles",
  ),
  KeSicActivity(
      "478110",
      "Retail sale via stalls and markets of food",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 478 · Retail sale via stalls and markets / Class 4781 · Retail sale via stalls and markets of food, beverages and tobacco products / Subclass 47811 · Retail sale via stalls and markets of food",
  ),
  KeSicActivity(
      "478120",
      "Retail sale via stalls and markets of beverages and tobacco products",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 478 · Retail sale via stalls and markets / Class 4781 · Retail sale via stalls and markets of food, beverages and tobacco products / Subclass 47812 · Retail sale via stalls and markets of beverages and tobacco products",
  ),
  KeSicActivity(
      "478200",
      "Retailsaleviastallsandmarketsoftextiles, clothing and footwear",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 478 · Retail sale via stalls and markets / Class 4782 · Retailsaleviastallsandmarketsoftextiles, clothing and footwear / Subclass 47820 · Retailsaleviastallsandmarketsoftextiles, clothing and footwear",
  ),
  KeSicActivity(
      "478900",
      "Retail sale via stalls and markets of other goods",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 478 · Retail sale via stalls and markets / Class 4789 · Retail sale via stalls and markets of other goods / Subclass 47890 · Retail sale via stalls and markets of other goods",
  ),
  KeSicActivity(
      "479100",
      "Retail sale via mail order houses or via Internet",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 479 · Retail trade not in stores, stalls or markets / Class 4791 · Retail sale via mail order houses or via Internet / Subclass 47910 · Retail sale via mail order houses or via Internet",
  ),
  KeSicActivity(
      "479900",
      "Other retail sale not in stores, stalls or markets",
      "Section G · Wholesale and retail trade; repair of motor vehicles and motorcycles / Division 47 · Retail trade, except of motor vehicles and motorcycles / Group 479 · Retail trade not in stores, stalls or markets / Class 4799 · Other retail sale not in stores, stalls or markets / Subclass 47990 · Other retail sale not in stores, stalls or markets",
  ),
  KeSicActivity(
      "491110",
      "Passenger rail transport between cities/ towns",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 491 · Transport via railways / Class 4911 · Passenger rail transport, interurban / Subclass 49111 · Passenger rail transport between cities/ towns",
  ),
  KeSicActivity(
      "491190",
      "Other Passenger rail transport",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 491 · Transport via railways / Class 4911 · Passenger rail transport, interurban / Subclass 49119 · Other Passenger rail transport",
  ),
  KeSicActivity(
      "491210",
      "Freight rail transport",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 491 · Transport via railways / Class 4912 · Freight rail transport / Subclass 49121 · Freight rail transport",
  ),
  KeSicActivity(
      "492110",
      "Short distance Passenger transport (Matatus and Mini buses)",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4921 · Urban and suburban passenger land transport / Subclass 49211 · Short distance Passenger transport (Matatus and Mini buses)",
  ),
  KeSicActivity(
      "492120",
      "Three wheelers Passenger Transport (TukTuk/Rickshaw)",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4921 · Urban and suburban passenger land transport / Subclass 49212 · Three wheelers Passenger Transport (TukTuk/Rickshaw)",
  ),
  KeSicActivity(
      "492130",
      "Motorcycle/Bicycle Passenger Transport (Boda Boda)",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4921 · Urban and suburban passenger land transport / Subclass 49213 · Motorcycle/Bicycle Passenger Transport (Boda Boda)",
  ),
  KeSicActivity(
      "492140",
      "Passenger rail transport within cities/ towns",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4921 · Urban and suburban passenger land transport / Subclass 49214 · Passenger rail transport within cities/ towns",
  ),
  KeSicActivity(
      "492210",
      "Scheduled and unscheduled long distance Bus Service",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4922 · Other passenger land transport / Subclass 49221 · Scheduled and Unscheduled long distance Bus Service",
  ),
  KeSicActivity(
      "492220",
      "Passenger transport activities related to Charters, excursions, Tours & Travels and other occasional coach services",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4922 · Other passenger land transport / Subclass 49222 · Passenger transport activities related to Charters, excursions, Tours & Travels and other occasional coach services",
  ),
  KeSicActivity(
      "492230",
      "Taxi operation and airport shuttles",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4922 · Other passenger land transport / Subclass 49223 · Taxi operation and airport shuttles",
  ),
  KeSicActivity(
      "492240",
      "School Transport and Transport of employees",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4922 · Other passenger land transport / Subclass 49224 · School Transport and Transport of employees",
  ),
  KeSicActivity(
      "492290",
      "Other forms of Passenger Transport ( e.g. Donkey, Mkokoteni)",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4922 · Other passenger land transport / Subclass 49229 · Other forms of Passenger Transport ( e.g. Donkey, Mkokoteni)",
  ),
  KeSicActivity(
      "492310",
      "Freight transport by road formal",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4923 · Freight transport by road / Subclass 49231 · Freight transport by road formal",
  ),
  KeSicActivity(
      "492321",
      "Freight transport by road informal(tractors)",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4923 · Freight transport by road / Subclass 49232 · Freight transport by road informal",
  ),
  KeSicActivity(
      "492329",
      "Freight transport by road informal(other forms)",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4923 · Freight transport by road / Subclass 49232 · Freight transport by road informal",
  ),
  KeSicActivity(
      "492330",
      "Hearse services",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4923 · Freight transport by road / Subclass 49233 · Hearse services",
  ),
  KeSicActivity(
      "492340",
      "Transport of waste and waste materials (excludes Honey suckers in 3700)",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4923 · Freight transport by road / Subclass 49234 · Transport of waste and waste materials (excludes Honey suckers in 3700)",
  ),
  KeSicActivity(
      "492350",
      "Furniture removal and Transportation services",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4923 · Freight transport by road / Subclass 49235 · Furniture removal and Transportation services",
  ),
  KeSicActivity(
      "492390",
      "Other Freight transport by road(e.g. handcarts and Animal drawn Carts)",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 492 · Other land transport / Class 4923 · Freight transport by road / Subclass 49239 · Other Freight transport by road(e.g. handcarts and Animal drawn Carts)",
  ),
  KeSicActivity(
      "493010",
      "Transport Petroleum products via pipeline",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 493 · Transport via pipeline / Class 4930 · Transport via pipeline / Subclass 49301 · Transport Petroleum products via pipeline",
  ),
  KeSicActivity(
      "493020",
      "Long distance transport of water via pipeline",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 493 · Transport via pipeline / Class 4930 · Transport via pipeline / Subclass 49302 · Long distance transport of water via pipeline",
  ),
  KeSicActivity(
      "493030",
      "Transport of gas via pipeline",
      "Section H · Transportation and storage / Division 49 · Land transport and transport via pipelines / Group 493 · Transport via pipeline / Class 4930 · Transport via pipeline / Subclass 49303 · Transport of gas via pipeline",
  ),
  KeSicActivity(
      "501110",
      "Transport of passengers overseas and coastal waters by ships(excluding cruise, excursion and sightseeing ships)",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 501 · Sea and coastal water transport / Class 5011 · Sea and coastal passenger water transport / Subclass 50111 · Transport of passengers overseas and coastal waters by ships(excluding cruise, excursion and sightseeing ships)",
  ),
  KeSicActivity(
      "501120",
      "Operation of excursion, cruise or sightseeing boats",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 501 · Sea and coastal water transport / Class 5011 · Sea and coastal passenger water transport / Subclass 50112 · Operation of excursion, cruise or sightseeing boats",
  ),
  KeSicActivity(
      "501130",
      "Operation of ferries",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 501 · Sea and coastal water transport / Class 5011 · Sea and coastal passenger water transport / Subclass 50113 · Operation of ferries",
  ),
  KeSicActivity(
      "501140",
      "Operation of Passenger boats",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 501 · Sea and coastal water transport / Class 5011 · Sea and coastal passenger water transport / Subclass 50114 · Operation of Passenger boats",
  ),
  KeSicActivity(
      "501150",
      "Renting of pleasure boats with crew",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 501 · Sea and coastal water transport / Class 5011 · Sea and coastal passenger water transport / Subclass 50115 · Renting of pleasure boats with crew",
  ),
  KeSicActivity(
      "501210",
      "Sea and Ocean Freight transport",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 501 · Sea and coastal water transport / Class 5012 · Sea and coastal freight water transport / Subclass 50121 · Sea and Ocean Freight transport",
  ),
  KeSicActivity(
      "501220",
      "inter-island freight transport",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 501 · Sea and coastal water transport / Class 5012 · Sea and coastal freight water transport / Subclass 50122 · inter-island freight transport",
  ),
  KeSicActivity(
      "501290",
      "Other forms of sea and ocean freight transport (e.g. Towing and pushing of sea vessels)",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 501 · Sea and coastal water transport / Class 5012 · Sea and coastal freight water transport / Subclass 50129 · Other forms of sea and ocean freight transport (e.g. Towing and pushing of sea vessels)",
  ),
  KeSicActivity(
      "502110",
      "Transport of passengers over inland waters by ships(excluding cruise, excursion and sightseeing ships)",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 502 · Inland water transport / Class 5021 · Inland passenger water transport / Subclass 50211 · Transport of passengers over inland waters by ships(excluding cruise, excursion and sightseeing ships)",
  ),
  KeSicActivity(
      "502120",
      "Operation of excursion, cruise or sightseeing boats",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 502 · Inland water transport / Class 5021 · Inland passenger water transport / Subclass 50212 · Operation of excursion, cruise or sightseeing boats",
  ),
  KeSicActivity(
      "502130",
      "Operation of inland ferries",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 502 · Inland water transport / Class 5021 · Inland passenger water transport / Subclass 50213 · Operation of inland ferries",
  ),
  KeSicActivity(
      "502140",
      "Operation of inland Passenger boats",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 502 · Inland water transport / Class 5021 · Inland passenger water transport / Subclass 50214 · Operation of inland Passenger boats",
  ),
  KeSicActivity(
      "502150",
      "Renting of inland pleasure boats with crew",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 502 · Inland water transport / Class 5021 · Inland passenger water transport / Subclass 50215 · Renting of inland pleasure boats with crew",
  ),
  KeSicActivity(
      "502210",
      "Inland Freight transport",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 502 · Inland water transport / Class 5022 · Inland freight water transport / Subclass 50221 · Inland Freight transport",
  ),
  KeSicActivity(
      "502220",
      "Inter-island freight transport",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 502 · Inland water transport / Class 5022 · Inland freight water transport / Subclass 50222 · Inter-island freight transport",
  ),
  KeSicActivity(
      "502290",
      "Other forms of inland freight transport (e.g. Towing and pushing of inland water vessels)",
      "Section H · Transportation and storage / Division 50 · Water transport / Group 502 · Inland water transport / Class 5022 · Inland freight water transport / Subclass 50229 · Other forms of inland freight transport (e.g. Towing and pushing of inland water vessels)",
  ),
  KeSicActivity(
      "511010",
      "Transport of Passengers by air over regular routes and on regular schedules",
      "Section H · Transportation and storage / Division 51 · Air transport / Group 511 · Passenger air transport / Class 5110 · Passenger air transport / Subclass 51101 · Transport of Passengers by air over regular routes and on regular schedules",
  ),
  KeSicActivity(
      "511020",
      "Charter flights for passengers(including renting of air transport equipment with operators)",
      "Section H · Transportation and storage / Division 51 · Air transport / Group 511 · Passenger air transport / Class 5110 · Passenger air transport / Subclass 51102 · Charter flights for passengers(including renting of air transport equipment with operators)",
  ),
  KeSicActivity(
      "511030",
      "Scenic and sightseeing flights ( including passenger of aeroclubs for instruction or pleasure)",
      "Section H · Transportation and storage / Division 51 · Air transport / Group 511 · Passenger air transport / Class 5110 · Passenger air transport / Subclass 51103 · Scenic and sightseeing flights ( including passenger of aeroclubs for instruction or pleasure)",
  ),
  KeSicActivity(
      "512010",
      "Transport of freight by air over regular routes and on regular schedules",
      "Section H · Transportation and storage / Division 51 · Air transport / Group 512 · Freight air transport / Class 5120 · Freight air transport / Subclass 51201 · Transport of freight by air over regular routes and on regular schedules",
  ),
  KeSicActivity(
      "512020",
      "Non Scheduled air Freight transport (including renting of air transport equipment with operators)",
      "Section H · Transportation and storage / Division 51 · Air transport / Group 512 · Freight air transport / Class 5120 · Freight air transport / Subclass 51202 · Non Scheduled air Freight transport (including renting of air transport equipment with operators)",
  ),
  KeSicActivity(
      "512030",
      "Launching of satellites and space vehicles",
      "Section H · Transportation and storage / Division 51 · Air transport / Group 512 · Freight air transport / Class 5120 · Freight air transport / Subclass 51203 · Launching of satellites and space vehicles",
  ),
  KeSicActivity(
      "512090",
      "Other Fright air transport (e.g. launching transport using drones)",
      "Section H · Transportation and storage / Division 51 · Air transport / Group 512 · Freight air transport / Class 5120 · Freight air transport / Subclass 51209 · Other Fright air transport (e.g. launching transport using drones)",
  ),
  KeSicActivity(
      "521010",
      "Grain Silos",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 521 · Warehousing and storage / Class 5210 · Warehousing and storage / Subclass 52101 · Grain Silos",
  ),
  KeSicActivity(
      "521020",
      "Custom Bonded warehouse",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 521 · Warehousing and storage / Class 5210 · Warehousing and storage / Subclass 52102 · Custom Bonded warehouse",
  ),
  KeSicActivity(
      "521030",
      "Cold storage , including blast freezing",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 521 · Warehousing and storage / Class 5210 · Warehousing and storage / Subclass 52103 · Cold storage , including blast freezing",
  ),
  KeSicActivity(
      "521040",
      "Storage tank",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 521 · Warehousing and storage / Class 5210 · Warehousing and storage / Subclass 52104 · Storage tank",
  ),
  KeSicActivity(
      "521050",
      "Storage of goods in foreign trade zones",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 521 · Warehousing and storage / Class 5210 · Warehousing and storage / Subclass 52105 · Storage of goods in foreign trade zones",
  ),
  KeSicActivity(
      "521060",
      "General warehousing and storage activities",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 521 · Warehousing and storage / Class 5210 · Warehousing and storage / Subclass 52106 · General warehousing and storage activities",
  ),
  KeSicActivity(
      "522110",
      "Operation of railway stations",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5221 · Service activities incidental to land transportation / Subclass 52211 · Operation of railway stations",
  ),
  KeSicActivity(
      "522120",
      "Operation of bus stations, stations for the handling of goods",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5221 · Service activities incidental to land transportation / Subclass 52212 · Operation of bus stations, stations for the handling of goods",
  ),
  KeSicActivity(
      "522130",
      "Operation of railroad infrastructure",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5221 · Service activities incidental to land transportation / Subclass 52213 · Operation of railroad infrastructure",
  ),
  KeSicActivity(
      "522140",
      "Operation of roads, bridges, tunnels, car parks or garages, bicycle parking",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5221 · Service activities incidental to land transportation / Subclass 52214 · Operation of roads, bridges, tunnels, car parks or garages, bicycle parking",
  ),
  KeSicActivity(
      "522150",
      "Breakdown services -towing and road side assistance",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5221 · Service activities incidental to land transportation / Subclass 52215 · Breakdown services -towing and road side assistance",
  ),
  KeSicActivity(
      "522200",
      "Service activities incidental to water transportation",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5222 · Service activities incidental to water transportation / Subclass 52220 · Service activities incidental to water transportation",
  ),
  KeSicActivity(
      "522310",
      "Operation of terminal facilities such as airway terminals etc",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5223 · Service activities incidental to air transportation / Subclass 52231 · Operation of terminal facilities such as airway terminals etc",
  ),
  KeSicActivity(
      "522320",
      "Airport and air-traffic-control activities",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5223 · Service activities incidental to air transportation / Subclass 52232 · Airport and air-traffic-control activities",
  ),
  KeSicActivity(
      "522330",
      "Ground service activities on airfields etc",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5223 · Service activities incidental to air transportation / Subclass 52233 · Ground service activities on airfields etc",
  ),
  KeSicActivity(
      "522340",
      "Firefighting and fire-prevention services at airport",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5223 · Service activities incidental to air transportation / Subclass 52234 · Firefighting and fire-prevention services at airport",
  ),
  KeSicActivity(
      "522410",
      "Loading and unloading of goods or passengers’ luggage irrespective of the Mode of transport used for transportation",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5224 · Cargo handling / Subclass 52241 · Loading and unloading of goods or passengers’ luggage irrespective of the Mode of transport used for transportation",
  ),
  KeSicActivity(
      "522420",
      "stevedoring",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5224 · Cargo handling / Subclass 52242 · stevedoring",
  ),
  KeSicActivity(
      "522430",
      "Loading and unloading of freight railway cars",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5224 · Cargo handling / Subclass 52243 · Loading and unloading of freight railway cars",
  ),
  KeSicActivity(
      "522910",
      "Forwarding of freight",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5229 · Other transportation support activities / Subclass 52291 · Forwarding of freight",
  ),
  KeSicActivity(
      "522920",
      "Logistics activities, i.e. planning, designing and supporting operations of transportation, warehousing and distribution",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5229 · Other transportation support activities / Subclass 52292 · Logistics activities, i.e. planning, designing and supporting operations of transportation, warehousing and distribution",
  ),
  KeSicActivity(
      "522930",
      "Issue and procurement of transport documents and waybills; Activities of customs agents; Activities of sea-freight forwarders and air-cargo agents; Brokerage for ship and aircraft space",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5229 · Other transportation support activities / Subclass 52293 · Issue and procurement of transport documents and waybills; Activities of customs agents; Activities of sea-freight forwarders and air-cargo agents; Brokerage for ship and aircraft space",
  ),
  KeSicActivity(
      "522940",
      "Arranging or organizing of transport operations by rail, road, sea or air; Organization of group and individual consignments (including pickup and delivery of goods and grouping of consignments)",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5229 · Other transportation support activities / Subclass 52294 · Arranging or organizing of transport operations by rail, road, sea or air; Organization of group and individual consignments (including pickup and delivery of goods and grouping of consignments)",
  ),
  KeSicActivity(
      "522950",
      "Goods-handling operations, e.g. temporary crating for the sole purpose of protecting the goods during transit, uncrating, sampling, weighing of goods",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 522 · Support activities for transportation / Class 5229 · Other transportation support activities / Subclass 52295 · Goods-handling operations, e.g. temporary crating for the sole purpose of protecting the goods during transit, uncrating, sampling, weighing of goods",
  ),
  KeSicActivity(
      "531000",
      "Postal activities",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 531 · Postal and courier activities / Class 5310 · Postal activities / Subclass 53100 · Postal activities",
  ),
  KeSicActivity(
      "532000",
      "Courier activities",
      "Section H · Transportation and storage / Division 52 · Warehousing and s support activities for transportation / Group 532 · Courier activities / Class 5320 · Courier activities / Subclass 53200 · Courier activities",
  ),
  KeSicActivity(
      "551011",
      "Hotels",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55101 · hotels ,resort and lodges",
  ),
  KeSicActivity(
      "551012",
      "Resort",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55101 · hotels ,resort and lodges",
  ),
  KeSicActivity(
      "551013",
      "Lodges",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55101 · hotels ,resort and lodges",
  ),
  KeSicActivity(
      "551020",
      "Guesthouses",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55102 · Guesthouses",
  ),
  KeSicActivity(
      "551031",
      "Suite / apartment hotels",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55103 · Suite / apartment hotels, cottages, visitor flats and bungalows",
  ),
  KeSicActivity(
      "551032",
      "Cottages",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55103 · Suite / apartment hotels, cottages, visitor flats and bungalows",
  ),
  KeSicActivity(
      "551033",
      "Visitor flats and bungalows",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55103 · Suite / apartment hotels, cottages, visitor flats and bungalows",
  ),
  KeSicActivity(
      "551040",
      "Lodgings",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55104 · Lodgings",
  ),
  KeSicActivity(
      "551050",
      "Youth hostels",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55105 · Youth hostels",
  ),
  KeSicActivity(
      "551090",
      "Other Short term accommodation activities n.e.c",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 551 · Short term accommodation activities / Class 5510 · Short term accommodation activities / Subclass 55109 · Other Short term accommodation activities",
  ),
  KeSicActivity(
      "552010",
      "Camping grounds",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 552 · Camping grounds, recreational vehicle parks and trailer parks / Class 5520 · Camping grounds, recreational vehicle parks and trailer parks / Subclass 55201 · Camping grounds",
  ),
  KeSicActivity(
      "552090",
      "Other recreational facilities e.g. recreational vehicle parks and trailer parks",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 552 · Camping grounds, recreational vehicle parks and trailer parks / Class 5520 · Camping grounds, recreational vehicle parks and trailer parks / Subclass 55209 · Other recreational facilities e.g. recreational vehicle parks and trailer parks",
  ),
  KeSicActivity(
      "559100",
      "Student residences/hostels",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 559 · Other accommodation / Class 5591 · Student residences/hostels / Subclass 55910 · Student residences/hostels",
  ),
  KeSicActivity(
      "559900",
      "Other accommodation except student residence",
      "Section I · Accommodation and food service activities / Division 55 · Accommodation / Group 559 · Other accommodation / Class 5599 · Other accommodation / Subclass 55990 · Other accommodation except student residence",
  ),
  KeSicActivity(
      "561011",
      "Restaurants",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 561 · Restaurants and mobile food service activities / Class 5610 · Restaurants and mobile food service activities / Subclass 56101 · Restaurants, cafeterias and fast-food restaurants",
  ),
  KeSicActivity(
      "561012",
      "Cafeterias",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 561 · Restaurants and mobile food service activities / Class 5610 · Restaurants and mobile food service activities / Subclass 56101 · Restaurants, cafeterias and fast-food restaurants",
  ),
  KeSicActivity(
      "561013",
      "Fast-food restaurants",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 561 · Restaurants and mobile food service activities / Class 5610 · Restaurants and mobile food service activities / Subclass 56101 · Restaurants, cafeterias and fast-food restaurants",
  ),
  KeSicActivity(
      "561020",
      "Take-out /take-away eating places",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 561 · Restaurants and mobile food service activities / Class 5610 · Restaurants and mobile food service activities / Subclass 56102 · Take-out eating places/take away",
  ),
  KeSicActivity(
      "561030",
      "Food preparation in market stalls/kiosks",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 561 · Restaurants and mobile food service activities / Class 5610 · Restaurants and mobile food service activities / Subclass 56103 · Food preparation in market stalls/kiosks",
  ),
  KeSicActivity(
      "561040",
      "Ice cream vendors",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 561 · Restaurants and mobile food service activities / Class 5610 · Restaurants and mobile food service activities / Subclass 56104 · Ice cream vendors",
  ),
  KeSicActivity(
      "561050",
      "Meat eateries",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 561 · Restaurants and mobile food service activities / Class 5610 · Restaurants and mobile food service activities / Subclass 56105 · Meat eateries",
  ),
  KeSicActivity(
      "561090",
      "Other food service activities n.e.c",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 561 · Restaurants and mobile food service activities / Class 5610 · Restaurants and mobile food service activities / Subclass 56109 · Other food service activities n.e.c",
  ),
  KeSicActivity(
      "562100",
      "Event catering",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 562 · Event catering and other food service activities / Class 5621 · Event catering / Subclass 56210 · Event catering",
  ),
  KeSicActivity(
      "562910",
      "Activities of food service contractors (e.g. for transportation companies)",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 562 · Event catering and other food service activities / Class 5629 · Other food service activities / Subclass 56291 · Activities of food service contractors (e.g. for transportation companies)",
  ),
  KeSicActivity(
      "562920",
      "Operation of food concessions at sports and similar facilities",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 562 · Event catering and other food service activities / Class 5629 · Other food service activities / Subclass 56292 · Operation of food concessions at sports and similar facilities",
  ),
  KeSicActivity(
      "562930",
      "Operation of canteens or cafeterias (e.g. for factories, offices, hospitals or schools) on a concession basis",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 562 · Event catering and other food service activities / Class 5629 · Other food service activities / Subclass 56293 · Operation of canteens or cafeterias (e.g. for factories, offices, hospitals or schools) on a concession basis",
  ),
  KeSicActivity(
      "563010",
      "Bars, lounges , taverns, beer parlours and pubs",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 563 · Beverage serving activities / Class 5630 · Beverage serving activities / Subclass 56301 · Bars, lounges , taverns, beer parlours and pubs",
  ),
  KeSicActivity(
      "563020",
      "Discotheques (with beverage serving predominant)",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 563 · Beverage serving activities / Class 5630 · Beverage serving activities / Subclass 56302 · Discotheques (with beverage serving predominant)",
  ),
  KeSicActivity(
      "563030",
      "Coffee shops",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 563 · Beverage serving activities / Class 5630 · Beverage serving activities / Subclass 56303 · Coffee shops",
  ),
  KeSicActivity(
      "563040",
      "Fruit juice bars",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 563 · Beverage serving activities / Class 5630 · Beverage serving activities / Subclass 56304 · Fruit juice bars",
  ),
  KeSicActivity(
      "563050",
      "Mobile beverage vendors",
      "Section I · Accommodation and food service activities / Division 56 · Food and beverage service activities / Group 563 · Beverage serving activities / Class 5630 · Beverage serving activities / Subclass 56305 · Mobile beverage vendors",
  ),
  KeSicActivity(
      "581110",
      "Publishingofbooks,brochures,leafletsand similar publications, including publishing encyclopedias (including on CD-ROM)",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 581 · Publishing of books, periodicals and other publishing activities / Class 5811 · Book publishing / Subclass 58111 · Publishingofbooks,brochures,leafletsand similar publications, including publishing encyclopedias (including on CD-ROM)",
  ),
  KeSicActivity(
      "581120",
      "Publishing of atlases, maps and charts",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 581 · Publishing of books, periodicals and other publishing activities / Class 5811 · Book publishing / Subclass 58112 · Publishing of atlases, maps and charts",
  ),
  KeSicActivity(
      "581130",
      "Publishing of audio books",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 581 · Publishing of books, periodicals and other publishing activities / Class 5811 · Book publishing / Subclass 58113 · Publishing of audio books",
  ),
  KeSicActivity(
      "581200",
      "Publishing of directories and mailing lists",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 581 · Publishing of books, periodicals and other publishing activities / Class 5812 · Publishing of directories and mailing lists / Subclass 58120 · Publishing of directories and mailing lists",
  ),
  KeSicActivity(
      "581310",
      "Publishing of newspapers",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 581 · Publishing of books, periodicals and other publishing activities / Class 5813 · Publishing of newspapers, journals and periodicals / Subclass 58131 · Publishing of newspapers",
  ),
  KeSicActivity(
      "581320",
      "Publishing of journals and periodicals",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 581 · Publishing of books, periodicals and other publishing activities / Class 5813 · Publishing of newspapers, journals and periodicals / Subclass 58132 · Publishing of journals and periodicals",
  ),
  KeSicActivity(
      "581900",
      "Other publishing activities",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 581 · Publishing of books, periodicals and other publishing activities / Class 5819 · Other publishing activities / Subclass 58190 · Other publishing activities",
  ),
  KeSicActivity(
      "582010",
      "Publishingof operatingsystemsandsystem software",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 582 · Software publishing / Class 5820 · Software publishing / Subclass 58201 · Publishingof operatingsystemsandsystem software",
  ),
  KeSicActivity(
      "582020",
      "Publishing of operating business and other applications",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 582 · Software publishing / Class 5820 · Software publishing / Subclass 58202 · Publishing of operating business and other applications",
  ),
  KeSicActivity(
      "582030",
      "Publishing of computer games for all platforms",
      "Section J · Information and communication / Division 58 · Publishing activities / Group 582 · Software publishing / Class 5820 · Software publishing / Subclass 58203 · Publishing of computer games for all platforms",
  ),
  KeSicActivity(
      "591110",
      "Production of motion picture",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5911 · Motion picture, video and television programme production activities / Subclass 59111 · Production of motion picture",
  ),
  KeSicActivity(
      "591120",
      "Video production",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5911 · Motion picture, video and television programme production activities / Subclass 59112 · Video production",
  ),
  KeSicActivity(
      "591130",
      "Production of television programmes or television commercials",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5911 · Motion picture, video and television programme production activities / Subclass 59113 · Production of television programmes or television commercials",
  ),
  KeSicActivity(
      "591210",
      "Post production activities of motion picture",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5912 · Motion picture, video and television programme post-production activities / Subclass 59121 · Post production activities of motion picture",
  ),
  KeSicActivity(
      "591220",
      "Post production activities of television programmes or television commercials",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5912 · Motion picture, video and television programme post-production activities / Subclass 59122 · Post production activities of television programmes or television commercials",
  ),
  KeSicActivity(
      "591230",
      "Post production activities of video production",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5912 · Motion picture, video and television programme post-production activities / Subclass 59123 · Post production activities of video production",
  ),
  KeSicActivity(
      "591310",
      "Motion picture distribution",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5913 · Motion picture, video and television programme distribution activities / Subclass 59131 · Motion picture distribution",
  ),
  KeSicActivity(
      "591320",
      "Distribution of video tapes, CD and DVDs",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5913 · Motion picture, video and television programme distribution activities / Subclass 59132 · Distribution of video tapes, CD and DVDs",
  ),
  KeSicActivity(
      "591330",
      "Distribution of television programme",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5913 · Motion picture, video and television programme distribution activities / Subclass 59133 · Distribution of television programme",
  ),
  KeSicActivity(
      "591410",
      "Motion picture or video tape projection in cinemas, in the open air or in other projection facilities",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5914 · Motion picture projection activities / Subclass 59141 · Motion picture or video tape projection in cinemas, in the open air or in other projection facilities",
  ),
  KeSicActivity(
      "591420",
      "Activities of cine-clubs",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 591 · Motion picture, video and television programme activities / Class 5914 · Motion picture projection activities / Subclass 59142 · Activities of cine-clubs",
  ),
  KeSicActivity(
      "592010",
      "Activities of sound recording in studio or elsewhere",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 592 · Sound recording and music publishing activities / Class 5920 · Sound recording and music publishing activities / Subclass 59201 · Activities of sound recording in studio or elsewhere",
  ),
  KeSicActivity(
      "592020",
      "Activities of music publishing",
      "Section J · Information and communication / Division 59 · Motion picture, video and television programme production, sound recording and music publishing activities / Group 592 · Sound recording and music publishing activities / Class 5920 · Sound recording and music publishing activities / Subclass 59202 · Activities of music publishing",
  ),
  KeSicActivity(
      "601011",
      "Over-the-air broadcasts",
      "Section J · Information and communication / Division 60 · Programming and broadcasting activities / Group 601 · Radio broadcasting / Class 6010 · Radio broadcasting / Subclass 60101 · Radio broadcasting over cable or satellite",
  ),
  KeSicActivity(
      "601012",
      "Radio broadcasting over cable or satellite",
      "Section J · Information and communication / Division 60 · Programming and broadcasting activities / Group 601 · Radio broadcasting / Class 6010 · Radio broadcasting / Subclass 60101 · Radio broadcasting over cable or satellite",
  ),
  KeSicActivity(
      "601020",
      "Radio broadcasting activities over the internet (internet radio stations)",
      "Section J · Information and communication / Division 60 · Programming and broadcasting activities / Group 601 · Radio broadcasting / Class 6010 · Radio broadcasting / Subclass 60102 · Radio broadcasting activities over the internet (internet radio stations)",
  ),
  KeSicActivity(
      "601090",
      "Radio broadcasting activities n.e.c",
      "Section J · Information and communication / Division 60 · Programming and broadcasting activities / Group 601 · Radio broadcasting / Class 6010 · Radio broadcasting / Subclass 60109 · Radio broadcasting activities n.e.c",
  ),
  KeSicActivity(
      "602010",
      "creation of a complete television channel programme( from purchased, self- produced progrogramme components or combination thereof)",
      "Section J · Information and communication / Division 60 · Programming and broadcasting activities / Group 602 · Television programming and broadcasting activities / Class 6020 · Television programming and broadcasting activities / Subclass 60201 · creation of a complete television channel programme( from purchased, self- produced progrogramme components or combination thereof)",
  ),
  KeSicActivity(
      "602020",
      "Programming of video-on-demand channels",
      "Section J · Information and communication / Division 60 · Programming and broadcasting activities / Group 602 · Television programming and broadcasting activities / Class 6020 · Television programming and broadcasting activities / Subclass 60202 · Programming of video-on-demand channels",
  ),
  KeSicActivity(
      "602090",
      "Television programming and broadcasting activities n.e.c",
      "Section J · Information and communication / Division 60 · Programming and broadcasting activities / Group 602 · Television programming and broadcasting activities / Class 6020 · Television programming and broadcasting activities / Subclass 60209 · Television programming and broadcasting activities n.e.c",
  ),
  KeSicActivity(
      "611000",
      "Wired telecommunications activities",
      "Section J · Information and communication / Division 61 · Telecommunications / Group 611 · Wired telecommunications activities / Class 6110 · Wired telecommunications activities / Subclass 61100 · Wired telecommunications activities",
  ),
  KeSicActivity(
      "612010",
      "Operating, maintaining or providing access to facilities for the transmission of voice, data, text, sound, and video using a wireless telecommunications infrastructure",
      "Section J · Information and communication / Division 61 · Telecommunications / Group 612 · Wireless telecommunications activities / Class 6120 · Wireless telecommunications activities / Subclass 61201 · Operating, maintaining or providing access to facilities for the transmission of voice,",
  ),
  KeSicActivity(
      "612020",
      "Provision of internet access by the operator of the wireless infrastructure",
      "Section J · Information and communication / Division 61 · Telecommunications / Group 612 · Wireless telecommunications activities / Class 6120 · Wireless telecommunications activities / Subclass 61202 · Provision of internet access by the operator of the wireless infrastructure",
  ),
  KeSicActivity(
      "612090",
      "Wireless telecommunications activities n.e.c",
      "Section J · Information and communication / Division 61 · Telecommunications / Group 612 · Wireless telecommunications activities / Class 6120 · Wireless telecommunications activities / Subclass 61209 · Wireless telecommunications activities n.e.c",
  ),
  KeSicActivity(
      "613000",
      "Satellite telecommunications activities",
      "Section J · Information and communication / Division 61 · Telecommunications / Group 613 · Satellite telecommunications activities / Class 6130 · Satellite telecommunications activities / Subclass 61300 · Satellite telecommunications activities",
  ),
  KeSicActivity(
      "619000",
      "Other telecommunications activities",
      "Section J · Information and communication / Division 61 · Telecommunications / Group 619 · Other telecommunications activities / Class 6190 · Other telecommunications activities / Subclass 61900 · Other telecommunications activities",
  ),
  KeSicActivity(
      "620110",
      "Designing the structure and content of, and/or writing the computer code necessary to create and implement",
      "Section J · Information and communication / Division 62 · Computer programming, consultancy a and related activities / Group 620 · Computer programming, consultancy and related activities / Class 6201 · Computer programming activities / Subclass 62011 · designing the structure and content of, and/or writing the computer code necessary to create and implement",
  ),
  KeSicActivity(
      "620120",
      "Customizing of software, i.e. modifying and configuring an existing application so that it is functional within the clients’ information system environment",
      "Section J · Information and communication / Division 62 · Computer programming, consultancy a and related activities / Group 620 · Computer programming, consultancy and related activities / Class 6201 · Computer programming activities / Subclass 62012 · Customizing of software, i.e. modifying and configuring an existing application so that it is functional within the clients’ information system environment",
  ),
  KeSicActivity(
      "620210",
      "Planning and designing of computer systems that integrate computer hardware, software and communication technologies",
      "Section J · Information and communication / Division 62 · Computer programming, consultancy a and related activities / Group 620 · Computer programming, consultancy and related activities / Class 6202 · Computer consultancy and computer facilities management activities / Subclass 62021 · Planning and designing of computer systems that integrate computer hardware, software and communication technologies",
  ),
  KeSicActivity(
      "620220",
      "Provision of on-site management and operation of clients’ computer systems and/or data processing facilities, as well as related support services",
      "Section J · Information and communication / Division 62 · Computer programming, consultancy a and related activities / Group 620 · Computer programming, consultancy and related activities / Class 6202 · Computer consultancy and computer facilities management activities / Subclass 62022 · Provision of on-site management and operation of clients’ computer systems and/or data processing facilities, as well as related support services",
  ),
  KeSicActivity(
      "620910",
      "computer disaster recovery",
      "Section J · Information and communication / Division 62 · Computer programming, consultancy a and related activities / Group 620 · Computer programming, consultancy and related activities / Class 6209 · Other information technology and computer service activities / Subclass 62091 · computer disaster recovery",
  ),
  KeSicActivity(
      "620920",
      "personal computers and software installation",
      "Section J · Information and communication / Division 62 · Computer programming, consultancy a and related activities / Group 620 · Computer programming, consultancy and related activities / Class 6209 · Other information technology and computer service activities / Subclass 62092 · personal computers and software installation",
  ),
  KeSicActivity(
      "631110",
      "provision of infrastructure",
      "Section J · Information and communication / Division 63 · Information service activities / Group 631 · Data processing, hosting and related activities; web portals / Class 6311 · Data processing, hosting and related activities / Subclass 63111 · provision of infrastructure",
  ),
  KeSicActivity(
      "631120",
      "Hosting services",
      "Section J · Information and communication / Division 63 · Information service activities / Group 631 · Data processing, hosting and related activities; web portals / Class 6311 · Data processing, hosting and related activities / Subclass 63112 · Hosting services",
  ),
  KeSicActivity(
      "631130",
      "Data processing activities",
      "Section J · Information and communication / Division 63 · Information service activities / Group 631 · Data processing, hosting and related activities; web portals / Class 6311 · Data processing, hosting and related activities / Subclass 63113 · Data processing activities",
  ),
  KeSicActivity(
      "631140",
      "Related activities",
      "Section J · Information and communication / Division 63 · Information service activities / Group 631 · Data processing, hosting and related activities; web portals / Class 6311 · Data processing, hosting and related activities / Subclass 63114 · Related activities",
  ),
  KeSicActivity(
      "631200",
      "Web portals",
      "Section J · Information and communication / Division 63 · Information service activities / Group 631 · Data processing, hosting and related activities; web portals / Class 6312 · Web portals / Subclass 63120 · Web portals",
  ),
  KeSicActivity(
      "639100",
      "News agency activities",
      "Section J · Information and communication / Division 63 · Information service activities / Group 639 · Other information service activities / Class 6391 · News agency activities / Subclass 63910 · News agency activities",
  ),
  KeSicActivity(
      "639900",
      "Other information service activities n.e.c",
      "Section J · Information and communication / Division 63 · Information service activities / Group 639 · Other information service activities / Class 6399 · Other information service activities n.e.c / Subclass 63990 · Other information service activities n.e.c",
  ),
  KeSicActivity(
      "641100",
      "Central banking",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6411 · Central banking / Subclass 64110 · Central banking",
  ),
  KeSicActivity(
      "641200",
      "Commercial banks",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6412 · Commercial banks / Subclass 64120 · Commercial banks",
  ),
  KeSicActivity(
      "641210",
      "Forex Bureaus",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 641 · Monetary intermediation / Class 6412 · Commercial banks / Subclass 64121 · Forex Bureaus",
  ),
  KeSicActivity(
      "641220",
      "Stock Brokers",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 641 · Monetary intermediation / Class 6412 · Commercial banks / Subclass 64122 · Stock Brokers",
  ),
  KeSicActivity(
      "641300",
      "Microfinance",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6413 · Microfinance / Subclass 64130 · Microfinance",
  ),
  KeSicActivity(
      "641400",
      "Mortgage Finance",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6414 · Mortgage Finance / Subclass 64140 · Mortgage Finance",
  ),
  KeSicActivity(
      "641500",
      "Saving and credit cooperative Societies",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6415 · Saving and credit cooperative Societies / Subclass 64150 · Saving and credit cooperative Societies",
  ),
  KeSicActivity(
      "641610",
      "Mobile money activities by Telco’s and Banks",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6416 · Mobile money services e.g. MPESA / Subclass 64161 · Mobile money activities by Telco’s and Banks",
  ),
  KeSicActivity(
      "641690",
      "Mobile money activities by Other Provides",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6416 · Mobile money services e.g. MPESA / Subclass 64169 · Mobile money activities by Other Provides",
  ),
  KeSicActivity(
      "641700",
      "Mobile money agents ( Mpesa, Tcash, Airtel Money, equitel)",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6417 · Mobile money agents ( Mpesa, Tcash, Airtel Money, equitel) / Subclass 64170 · Mobile money agents ( Mpesa, Tcash, Airtel Money, equitel)",
  ),
  KeSicActivity(
      "641800",
      "Banking agents (Coop Jirani, KCB Mtaani)",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6418 · Banking agents (Coop Jirani, KCB Mtaani) / Subclass 64180 · Banking agents (Coop Jirani, KCB Mtaani)",
  ),
  KeSicActivity(
      "641990",
      "Other monetary intermediation n.e.c",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 641 · Monetary intermediation / Class 6419 · Other monetary intermediation n.e.c / Subclass 64199 · Other monetary intermediation n.e.c",
  ),
  KeSicActivity(
      "642000",
      "Activities of holding companies",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 642 · Activities of holding companies / Class 6420 · Activities of holding companies / Subclass 64200 · Activities of holding companies",
  ),
  KeSicActivity(
      "643000",
      "Trusts, funds and similar financial entities",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 643 · Trusts, funds and similar financial entities / Class 6430 · Trusts, funds and similar financial entities / Subclass 64300 · Trusts, funds and similar financial entities",
  ),
  KeSicActivity(
      "649100",
      "Financial leasing",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 649 · Other financial service activities, except insurance and pension funding activities / Class 6491 · Financial leasing / Subclass 64910 · Financial leasing",
  ),
  KeSicActivity(
      "649210",
      "Thrift and loan societies and credit associations",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 649 · Other financial service activities, except insurance and pension funding activities / Class 6492 · Other credit granting / Subclass 64921 · Thrift and loan societies and credit associations",
  ),
  KeSicActivity(
      "649220",
      "Pawn brokerage",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 649 · Other financial service activities, except insurance and pension funding activities / Class 6492 · Other credit granting / Subclass 64922 · Pawn brokerage",
  ),
  KeSicActivity(
      "649230",
      "Money-lending/Shylocks",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 649 · Other financial service activities, except insurance and pension funding activities / Class 6492 · Other credit granting / Subclass 64923 · Money-lending/Shylocks",
  ),
  KeSicActivity(
      "649290",
      "Other credit agencies n.e.c. (e.g. motor finance)",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 649 · Other financial service activities, except insurance and pension funding activities / Class 6492 · Other credit granting / Subclass 64929 · Other credit agencies n.e.c. (e.g. motor finance)",
  ),
  KeSicActivity(
      "649900",
      "Other financial service activities, except insurance and pension funding activities, n.e.c",
      "Section K · Financial and insurance activities / Division 64 · Financial service activities, except insurance and pension f funding / Group 649 · Other financial service activities, except insurance and pension funding activities / Class 6499 · Other financial service activities, except insurance and pension funding activities, n.e.c / Subclass 64990 · Other financial service activities, except insurance and pension funding activities, n.e.c",
  ),
  KeSicActivity(
      "651100",
      "Life insurance",
      "Section K · Financial and insurance activities / Division 65 · Insurance, r reinsurance and pension funding, except compulsory social security / Group 651 · Insurance / Class 6511 · Life insurance / Subclass 65110 · Life insurance",
  ),
  KeSicActivity(
      "651210",
      "Health insurance",
      "Section K · Financial and insurance activities / Division 65 · Insurance, r reinsurance and pension funding, except compulsory social security / Group 651 · Insurance / Class 6512 · Non-life insurance / Subclass 65121 · Health insurance",
  ),
  KeSicActivity(
      "651290",
      "Other Non-life insurance",
      "Section K · Financial and insurance activities / Division 65 · Insurance, r reinsurance and pension funding, except compulsory social security / Group 651 · Insurance / Class 6512 · Non-life insurance / Subclass 65129 · Other Non-life insurance",
  ),
  KeSicActivity(
      "652000",
      "Reinsurance",
      "Section K · Financial and insurance activities / Division 65 · Insurance, r reinsurance and pension funding, except compulsory social security / Group 652 · Reinsurance / Class 6520 · Reinsurance / Subclass 65200 · Reinsurance",
  ),
  KeSicActivity(
      "653000",
      "Pension funding",
      "Section K · Financial and insurance activities / Division 65 · Insurance, r reinsurance and pension funding, except compulsory social security / Group 653 · Pension funding / Class 6530 · Pension funding / Subclass 65300 · Pension funding",
  ),
  KeSicActivity(
      "661100",
      "Administration of financial markets",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 661 · Activities auxiliary to financial service activities, except insurance and pension funding / Class 6611 · Administration of financial markets / Subclass 66110 · Administration of financial markets",
  ),
  KeSicActivity(
      "661290",
      "Other Security and commodity contracts brokerage n.e.c",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 661 · Activities auxiliary to financial service activities, except insurance and pension funding / Class 6612 · Security and commodity contracts brokerage / Subclass 66129 · Other Security and commodity contracts brokerage n.e.c",
  ),
  KeSicActivity(
      "661910",
      "Trustee, fiduciary and custody services on a fee or contract basis",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 661 · Activities auxiliary to financial service activities, except insurance and pension funding / Class 6619 · Other activities auxiliary to financial service activities / Subclass 66191 · Trustee, fiduciary and custody services on a fee or contract basis",
  ),
  KeSicActivity(
      "661920",
      "Financial transaction processing and settlement activities, including for credit card transactions",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 661 · Activities auxiliary to financial service activities, except insurance and pension funding / Class 6619 · Other activities auxiliary to financial service activities / Subclass 66192 · Financial transaction processing and settlement activities, including for credit card transactions",
  ),
  KeSicActivity(
      "661930",
      "Investment advisory services",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 661 · Activities auxiliary to financial service activities, except insurance and pension funding / Class 6619 · Other activities auxiliary to financial service activities / Subclass 66193 · Investment advisory services",
  ),
  KeSicActivity(
      "661940",
      "Activities of mortgage advisers and brokers",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 661 · Activities auxiliary to financial service activities, except insurance and pension funding / Class 6619 · Other activities auxiliary to financial service activities / Subclass 66194 · Activities of mortgage advisers and brokers",
  ),
  KeSicActivity(
      "662100",
      "Risk and damage evaluation",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 662 · Activities auxiliary to insurance and pension funding / Class 6621 · Risk and damage evaluation / Subclass 66210 · Risk and damage evaluation",
  ),
  KeSicActivity(
      "662210",
      "Activities of insurance agents",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 662 · Activities auxiliary to insurance and pension funding / Class 6622 · Activities of insurance agents and brokers / Subclass 66221 · Activities of insurance agents",
  ),
  KeSicActivity(
      "662220",
      "Activities of insurance brokers",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 662 · Activities auxiliary to insurance and pension funding / Class 6622 · Activities of insurance agents and brokers / Subclass 66222 · Activities of insurance brokers",
  ),
  KeSicActivity(
      "662900",
      "Other activities auxiliary to insurance and pension funding",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 662 · Activities auxiliary to insurance and pension funding / Class 6629 · Other activities auxiliary to insurance and pension funding / Subclass 66290 · Other activities auxiliary to insurance and pension funding",
  ),
  KeSicActivity(
      "663010",
      "Management of pension funds",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 663 · Fund management activities / Class 6630 · Fund management activities / Subclass 66301 · Management of pension funds",
  ),
  KeSicActivity(
      "663020",
      "Management of mutual funds",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 663 · Fund management activities / Class 6630 · Fund management activities / Subclass 66302 · Management of mutual funds",
  ),
  KeSicActivity(
      "663030",
      "Management of other investment funds",
      "Section K · Financial and insurance activities / Division 66 · Activities auxiliary to financial service and insurance activities / Group 663 · Fund management activities / Class 6630 · Fund management activities / Subclass 66303 · Management of other investment funds",
  ),
  KeSicActivity(
      "681010",
      "Buying and selling of residential and nonresidential buildings and land",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 681 · Real estate activities with own or leased property / Class 6810 · Real estate activities with own or leased property / Subclass 68101 · Buying and selling of residential and non- residential buildings and land",
  ),
  KeSicActivity(
      "681021",
      "residential",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 681 · Real estate activities with own or leased property / Class 6810 · Real estate activities with own or leased property / Subclass 68102 · Renting and operating of self-owned or leased real estate",
  ),
  KeSicActivity(
      "681022",
      "non residential",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 681 · Real estate activities with own or leased property / Class 6810 · Real estate activities with own or leased property / Subclass 68102 · Renting and operating of self-owned or leased real estate",
  ),
  KeSicActivity(
      "681030",
      "Operating of furnished/serviced apartments (owned or leased)",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 681 · Real estate activities with own or leased property / Class 6810 · Real estate activities with own or leased property / Subclass 68103 · Operating of furnished/serviced apartments (owned or leased)",
  ),
  KeSicActivity(
      "681040",
      "Real estate developers of own property for leasing or sale( construction work done by a separate entity at a fee)",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 681 · Real estate activities with own or leased property / Class 6810 · Real estate activities with own or leased property / Subclass 68104 · Real estate developers of own property for leasing or sale( construction work done by a separate entity at a fee)",
  ),
  KeSicActivity(
      "681090",
      "Real estate activities with own or leased property n.e.c",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 681 · Real estate activities with own or leased property / Class 6810 · Real estate activities with own or leased property / Subclass 68109 · Real estate activities with own or leased property n.e.c",
  ),
  KeSicActivity(
      "682010",
      "activities of real estate agents and brokers",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 682 · Real estate activities on a fee or contract basis / Class 6820 · Real estate activities on a fee or contract basis / Subclass 68201 · activities of real estate agents and brokers",
  ),
  KeSicActivity(
      "682020",
      "Intermediation in buying, selling and renting of real estate on a fee or contract basis",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 682 · Real estate activities on a fee or contract basis / Class 6820 · Real estate activities on a fee or contract basis / Subclass 68202 · Intermediation in buying, selling and renting of real estate on a fee or contract basis",
  ),
  KeSicActivity(
      "682030",
      "Management of real estate on a fee or contract basis",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 682 · Real estate activities on a fee or contract basis / Class 6820 · Real estate activities on a fee or contract basis / Subclass 68203 · Management of real estate on a fee or contract basis",
  ),
  KeSicActivity(
      "682040",
      "Appraisal services for real estate",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 682 · Real estate activities on a fee or contract basis / Class 6820 · Real estate activities on a fee or contract basis / Subclass 68204 · Appraisal services for real estate",
  ),
  KeSicActivity(
      "682090",
      "Real estate activities on a fee or contract basis n.e.c",
      "Section L · Real estate activities / Division 68 · Real estate activities / Group 682 · Real estate activities on a fee or contract basis / Class 6820 · Real estate activities on a fee or contract basis / Subclass 68209 · Real estate activities on a fee or contract basis n.e.c",
  ),
  KeSicActivity(
      "691000",
      "Legal activities",
      "Section M · Professional, scientific and technical activities / Division 69 · Legal and accounting activities / Group 691 · Legal activities / Class 6910 · Legal activities / Subclass 69100 · Legal activities",
  ),
  KeSicActivity(
      "692010",
      "Accounting and bookkeeping",
      "Section M · Professional, scientific and technical activities / Division 69 · Legal and accounting activities / Group 692 · Accounting, bookkeeping and auditing activities; tax consultancy / Class 6920 · Accounting, bookkeeping and auditing activities; tax consultancy / Subclass 69201 · Accounting and bookkeeping",
  ),
  KeSicActivity(
      "692020",
      "Auditing activities",
      "Section M · Professional, scientific and technical activities / Division 69 · Legal and accounting activities / Group 692 · Accounting, bookkeeping and auditing activities; tax consultancy / Class 6920 · Accounting, bookkeeping and auditing activities; tax consultancy / Subclass 69202 · Auditing activities",
  ),
  KeSicActivity(
      "692030",
      "Tax consultancy",
      "Section M · Professional, scientific and technical activities / Division 69 · Legal and accounting activities / Group 692 · Accounting, bookkeeping and auditing activities; tax consultancy / Class 6920 · Accounting, bookkeeping and auditing activities; tax consultancy / Subclass 69203 · Tax consultancy",
  ),
  KeSicActivity(
      "701000",
      "Activities of head offices",
      "Section M · Professional, scientific and technical activities / Division 70 · Activities of head offices; management c consultancy activities / Group 701 · Activities of head offices / Class 7010 · Activities of head offices / Subclass 70100 · Activities of head offices",
  ),
  KeSicActivity(
      "702000",
      "Management consultancy activities",
      "Section M · Professional, scientific and technical activities / Division 70 · Activities of head offices; management c consultancy activities / Group 702 · Management consultancy activities / Class 7020 · Management consultancy activities / Subclass 70200 · Management consultancy activities",
  ),
  KeSicActivity(
      "711011",
      "Building design and drafting",
      "Section M · Professional, scientific and technical activities / Division 71 · Architectural and engineering activities; t technical testing and analysis / Group 711 · Architectural and engineering activities and related technical consultancy / Class 7110 · Architectural and engineering activities and related technical consultancy / Subclass 71101 · Architectural consulting activities",
  ),
  KeSicActivity(
      "711012",
      "Town and city planning and landscape architecture",
      "Section M · Professional, scientific and technical activities / Division 71 · Architectural and engineering activities; t technical testing and analysis / Group 711 · Architectural and engineering activities and related technical consultancy / Class 7110 · Architectural and engineering activities and related technical consultancy / Subclass 71101 · Architectural consulting activities",
  ),
  KeSicActivity(
      "711020",
      "Engineering design and consulting activities",
      "Section M · Professional, scientific and technical activities / Division 71 · Architectural and engineering activities; t technical testing and analysis / Group 711 · Architectural and engineering activities and related technical consultancy / Class 7110 · Architectural and engineering activities and related technical consultancy / Subclass 71102 · Engineering design and consulting activities",
  ),
  KeSicActivity(
      "711030",
      "Environmental engineering design and consultancy services",
      "Section M · Professional, scientific and technical activities / Division 71 · Architectural and engineering activities; t technical testing and analysis / Group 711 · Architectural and engineering activities and related technical consultancy / Class 7110 · Architectural and engineering activities and related technical consultancy / Subclass 71103 · Environmental engineering design and consultancy services",
  ),
  KeSicActivity(
      "711040",
      "land and boundary surveying activities including cartographic and spatial information activities",
      "Section M · Professional, scientific and technical activities / Division 71 · Architectural and engineering activities; t technical testing and analysis / Group 711 · Architectural and engineering activities and related technical consultancy / Class 7110 · Architectural and engineering activities and related technical consultancy / Subclass 71104 · land and boundary surveying activities including cartographic and spatial information activities",
  ),
  KeSicActivity(
      "712000",
      "Technical testing and analysis",
      "Section M · Professional, scientific and technical activities / Division 71 · Architectural and engineering activities; t technical testing and analysis / Group 712 · Technical testing and analysis / Class 7120 · Technical testing and analysis / Subclass 71200 · Technical testing and analysis",
  ),
  KeSicActivity(
      "721000",
      "Research and experimental development on natural sciences and engineering",
      "Section M · Professional, scientific and technical activities / Division 72 · Scientific research and development / Group 721 · Research and experimental development on natural sciences and engineering / Class 7210 · Research and experimental development on natural sciences and engineering / Subclass 72100 · Research and experimental development on natural sciences and engineering",
  ),
  KeSicActivity(
      "722000",
      "Research and experimental development on social sciences and humanities",
      "Section M · Professional, scientific and technical activities / Division 72 · Scientific research and development / Group 722 · Research and experimental development on social sciences and humanities / Class 7220 · Research and experimental development on social sciences and humanities / Subclass 72200 · Research and experimental development on social sciences and humanities",
  ),
  KeSicActivity(
      "731010",
      "Creation and realization of advertising campaigns:",
      "Section M · Professional, scientific and technical activities / Division 73 · Advertising and market research / Group 731 · Advertising / Class 7310 · Advertising / Subclass 73101 · creation and realization of advertising campaigns:",
  ),
  KeSicActivity(
      "731020",
      "Conducting marketing campaigns and other advertising services aimed at attracting and retaining customers",
      "Section M · Professional, scientific and technical activities / Division 73 · Advertising and market research / Group 731 · Advertising / Class 7310 · Advertising / Subclass 73102 · Conducting marketing campaigns and other advertising services aimed at attracting and retaining customers",
  ),
  KeSicActivity(
      "732000",
      "Market research and public opinion polling",
      "Section M · Professional, scientific and technical activities / Division 73 · Advertising and market research / Group 732 · Market research and public opinionpolling / Class 7320 · Market research and public opinion polling / Subclass 73200 · Market research and public opinion polling",
  ),
  KeSicActivity(
      "741010",
      "Fashion design related to textiles, wearing apparel, shoes, jewelry, furniture and other fashion goods as well as other personal or household goods",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 741 · Specialized design activities / Class 7410 · Specialized design activities / Subclass 74101 · Fashion design related to textiles, wearing apparel, shoes, jewelry, furniture and other fashion goods as well as other personal or household goods",
  ),
  KeSicActivity(
      "741020",
      "Activities of graphic and industrial design,",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 741 · Specialized design activities / Class 7410 · Specialized design activities / Subclass 74102 · Activities of graphic and industrial design,",
  ),
  KeSicActivity(
      "741030",
      "Activities of interior decorators",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 741 · Specialized design activities / Class 7410 · Specialized design activities / Subclass 74103 · Activities of interior decorators",
  ),
  KeSicActivity(
      "742010",
      "Commercial and consumer photograph production; and microfilming of documents",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 742 · Photographic activities / Class 7420 · Photographic activities / Subclass 74201 · Commercial and consumer photograph production; and microfilming of documents",
  ),
  KeSicActivity(
      "742020",
      "Film processing",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 742 · Photographic activities / Class 7420 · Photographic activities / Subclass 74202 · Film processing",
  ),
  KeSicActivity(
      "742030",
      "Activities of photojournalists",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 742 · Photographic activities / Class 7420 · Photographic activities / Subclass 74203 · Activities of photojournalists",
  ),
  KeSicActivity(
      "749010",
      "Activities of quantity surveyors",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 749 · Other professional, scientific and technical activities n.e.c / Class 7490 · Other professional, scientific and technical activities n.e.c / Subclass 74901 · Activities of quantity surveyors",
  ),
  KeSicActivity(
      "749020",
      "Security consulting",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 749 · Other professional, scientific and technical activities n.e.c / Class 7490 · Other professional, scientific and technical activities n.e.c / Subclass 74902 · Security consulting",
  ),
  KeSicActivity(
      "749030",
      "Agronomy consulting",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 749 · Other professional, scientific and technical activities n.e.c / Class 7490 · Other professional, scientific and technical activities n.e.c / Subclass 74903 · Agronomy consulting",
  ),
  KeSicActivity(
      "749090",
      "Other professional, scientific and technical activities n.e.c",
      "Section M · Professional, scientific and technical activities / Division 74 · Other professional, s scientific and technical activities / Group 749 · Other professional, scientific and technical activities n.e.c / Class 7490 · Other professional, scientific and technical activities n.e.c / Subclass 74909 · Other professional, scientific and technical activities n.e.c",
  ),
  KeSicActivity(
      "750000",
      "Veterinary activities",
      "Section M · Professional, scientific and technical activities / Division 75 · Veterinary activities / Group 750 · Veterinary activities / Class 7500 · Veterinary activities / Subclass 75000 · Veterinary activities",
  ),
  KeSicActivity(
      "771010",
      "Renting and leasing of passenger vehicles",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 771 · Renting and leasing of motor vehicles / Class 7710 · Renting and leasing of motor vehicles / Subclass 77101 · Renting and leasing of passenger vehicles",
  ),
  KeSicActivity(
      "771020",
      "Renting and leasing of trucks and trailers",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 771 · Renting and leasing of motor vehicles / Class 7710 · Renting and leasing of motor vehicles / Subclass 77102 · Renting and leasing of trucks and trailers",
  ),
  KeSicActivity(
      "771090",
      "Renting and leasing of other motor vehicles n.e.c",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 771 · Renting and leasing of motor vehicles / Class 7710 · Renting and leasing of motor vehicles / Subclass 77109 · Renting and leasing of other motor vehicles n.e.c",
  ),
  KeSicActivity(
      "772100",
      "Renting and leasing of recreational and sports goods",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 772 · Renting and leasing of personal and household goods / Class 7721 · Renting and leasing of recreational and sports goods / Subclass 77210 · Renting and leasing of recreational and sports goods",
  ),
  KeSicActivity(
      "772200",
      "Renting of video tapes and disks",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 772 · Renting and leasing of personal and household goods / Class 7722 · Renting of video tapes and disks / Subclass 77220 · Renting of video tapes and disks",
  ),
  KeSicActivity(
      "772910",
      "Renting of tent, furniture, pottery and glass, kitchen and tableware, utensils,",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 772 · Renting and leasing of personal and household goods / Class 7729 · Renting and leasing of other personal and household goods / Subclass 77291 · Renting of tent, furniture, pottery and glass, kitchen and tableware, utensils,",
  ),
  KeSicActivity(
      "772920",
      "Renting of household electrical and electronic equipment etc",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 772 · Renting and leasing of personal and household goods / Class 7729 · Renting and leasing of other personal and household goods / Subclass 77292 · Renting of household electrical and electronic equipment etc",
  ),
  KeSicActivity(
      "772990",
      "Renting and leasing of other personal and household goods n.e.c",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 772 · Renting and leasing of personal and household goods / Class 7729 · Renting and leasing of other personal and household goods / Subclass 77299 · Renting and leasing of other personal and household goods n.e.c",
  ),
  KeSicActivity(
      "773010",
      "Renting and operational leasing, without operator, of other machinery and equipment that are generally used as capital goods by industries:",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 773 · Renting and leasing of other machinery, equipment and tangible goods / Class 7730 · Renting and leasing of other machinery, equipment and tangible goods / Subclass 77301 · Renting and operational leasing, without operator, of other machinery and equipment that are generally used as capital goods by industries:",
  ),
  KeSicActivity(
      "773020",
      "Renting and operational leasing of transport equipment without operator",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 773 · Renting and leasing of other machinery, equipment and tangible goods / Class 7730 · Renting and leasing of other machinery, equipment and tangible goods / Subclass 77302 · Renting and operational leasing of transport equipment without operator",
  ),
  KeSicActivity(
      "773030",
      "Renting and operational leasing of agricultural, fishery and forestry machinery and equipment without operator:",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 773 · Renting and leasing of other machinery, equipment and tangible goods / Class 7730 · Renting and leasing of other machinery, equipment and tangible goods / Subclass 77303 · Renting and operational leasing of agricultural, fishery and forestry machinery and equipment without operator:",
  ),
  KeSicActivity(
      "773040",
      "Renting and operational leasing of construction and civil-engineering machinery and equipment without operator:",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 773 · Renting and leasing of other machinery, equipment and tangible goods / Class 7730 · Renting and leasing of other machinery, equipment and tangible goods / Subclass 77304 · Renting and operational leasing of construction and civil-engineering machinery and equipment without operator:",
  ),
  KeSicActivity(
      "773090",
      "Renting and leasing of other machinery, equipment and tangible goods n.e.c",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 773 · Renting and leasing of other machinery, equipment and tangible goods / Class 7730 · Renting and leasing of other machinery, equipment and tangible goods / Subclass 77309 · Renting and leasing of other machinery, equipment and tangible goods n.e.c",
  ),
  KeSicActivity(
      "774000",
      "Leasing of intellectual property and similar products, except copyrighted works",
      "Section N · Administrative and support service activities / Division 77 · Rental and leasing activities / Group 774 · Leasing of intellectual property and similar products, except copyrighted works / Class 7740 · Leasing of intellectual property and similar products, except copyrighted works / Subclass 77400 · Leasing of intellectual property and similar products, except copyrighted works",
  ),
  KeSicActivity(
      "781000",
      "Activities of employment placement agencies",
      "Section N · Administrative and support service activities / Division 78 · Employment activities / Group 781 · Activities of employment placement agencies / Class 7810 · Activities of employment placement agencies / Subclass 78100 · Activities of employment placement agencies",
  ),
  KeSicActivity(
      "782000",
      "Temporary employment agency activities",
      "Section N · Administrative and support service activities / Division 78 · Employment activities / Group 782 · Temporary employment agency activities / Class 7820 · Temporary employment agency activities / Subclass 78200 · Temporary employment agency activities",
  ),
  KeSicActivity(
      "783000",
      "Other human resources provision",
      "Section N · Administrative and support service activities / Division 78 · Employment activities / Group 783 · Other human resources provision / Class 7830 · Other human resources provision / Subclass 78300 · Other human resources provision",
  ),
  KeSicActivity(
      "791100",
      "Travel agency activities",
      "Section N · Administrative and support service activities / Division 79 · Travel agency, tour operator, reservation service and related activities / Group 791 · Travel agency and tour operator activities / Class 7911 · Travel agency activities / Subclass 79110 · Travel agency activities",
  ),
  KeSicActivity(
      "791200",
      "Tour operator activities",
      "Section N · Administrative and support service activities / Division 79 · Travel agency, tour operator, reservation service and related activities / Group 791 · Travel agency and tour operator activities / Class 7912 · Tour operator activities / Subclass 79120 · Tour operator activities",
  ),
  KeSicActivity(
      "799000",
      "Other reservation service and related activities",
      "Section N · Administrative and support service activities / Division 79 · Travel agency, tour operator, reservation service and related activities / Group 799 · Other reservation service and related activities / Class 7990 · Other reservation service and related activities / Subclass 79900 · Other reservation service and related activities",
  ),
  KeSicActivity(
      "801000",
      "Private security activities",
      "Section N · Administrative and support service activities / Division 80 · Security and investigation activities / Group 801 · Private security activities / Class 8010 · Private security activities / Subclass 80100 · Private security activities",
  ),
  KeSicActivity(
      "802000",
      "Security systems service activities",
      "Section N · Administrative and support service activities / Division 80 · Security and investigation activities / Group 802 · Security systems service activities / Class 8020 · Security systems service activities / Subclass 80200 · Security systems service activities",
  ),
  KeSicActivity(
      "803000",
      "Investigation activities",
      "Section N · Administrative and support service activities / Division 80 · Security and investigation activities / Group 803 · Investigation activities / Class 8030 · Investigation activities / Subclass 80300 · Investigation activities",
  ),
  KeSicActivity(
      "811000",
      "Combined facilities support activities",
      "Section N · Administrative and support service activities / Division 81 · Services to buildings and landscape activities / Group 811 · Combined facilities support activities / Class 8110 · Combined facilities support activities / Subclass 81100 · Combined facilities support activities",
  ),
  KeSicActivity(
      "812100",
      "General cleaning of buildings",
      "Section N · Administrative and support service activities / Division 81 · Services to buildings and landscape activities / Group 812 · Cleaning activities / Class 8121 · General cleaning of buildings / Subclass 81210 · General cleaning of buildings",
  ),
  KeSicActivity(
      "812910",
      "disinfecting and exterminating activities",
      "Section N · Administrative and support service activities / Division 81 · Services to buildings and landscape activities / Group 812 · Cleaning activities / Class 8129 · Other building and industrial cleaning activities / Subclass 81291 · disinfecting and exterminating activities",
  ),
  KeSicActivity(
      "812920",
      "cleaning of trains, planes, etc",
      "Section N · Administrative and support service activities / Division 81 · Services to buildings and landscape activities / Group 812 · Cleaning activities / Class 8129 · Other building and industrial cleaning activities / Subclass 81292 · cleaning of trains, planes, etc",
  ),
  KeSicActivity(
      "812930",
      "Exterior cleaning of buildings of all types, including offices, factories, shops, institutionsand other business and professional premises and multiunit residential buildings",
      "Section N · Administrative and support service activities / Division 81 · Services to buildings and landscape activities / Group 812 · Cleaning activities / Class 8129 · Other building and industrial cleaning activities / Subclass 81293 · Exterior cleaning of buildings of all types, including offices, factories, shops, institutions and other business and professional premises and multiunit residential buildings",
  ),
  KeSicActivity(
      "812990",
      "Other building and industrial cleaning activities, n.e.c",
      "Section N · Administrative and support service activities / Division 81 · Services to buildings and landscape activities / Group 812 · Cleaning activities / Class 8129 · Other building and industrial cleaning activities / Subclass 81299 · Other building and industrial cleaning activities, n.e.c",
  ),
  KeSicActivity(
      "813000",
      "Landscape care and maintenance service activities",
      "Section N · Administrative and support service activities / Division 81 · Services to buildings and landscape activities / Group 813 · Landscape care and maintenance service activities / Class 8130 · Landscape care and maintenance service activities / Subclass 81300 · Landscape care and maintenance service activities",
  ),
  KeSicActivity(
      "821100",
      "Combined office administrative service activities",
      "Section N · Administrative and support service activities / Division 82 · Office administrative, office support and other business support activities / Group 821 · Office administrative and support activities / Class 8211 · Combined office administrative service activities / Subclass 82110 · Combined office administrative service activities",
  ),
  KeSicActivity(
      "821900",
      "Photocopying, document preparation and other specialized office support activities",
      "Section N · Administrative and support service activities / Division 82 · Office administrative, office support and other business support activities / Group 821 · Office administrative and support activities / Class 8219 · Photocopying, document preparation and other specialized office support activities / Subclass 82190 · Photocopying, document preparation and other specialized office support activities",
  ),
  KeSicActivity(
      "822000",
      "Activities of call centres",
      "Section N · Administrative and support service activities / Division 82 · Office administrative, office support and other business support activities / Group 822 · Activities of call centres / Class 8220 · Activities of call centres / Subclass 82200 · Activities of call centres",
  ),
  KeSicActivity(
      "823000",
      "Organization of conventions and trade shows",
      "Section N · Administrative and support service activities / Division 82 · Office administrative, office support and other business support activities / Group 823 · Organization of conventions and trade shows / Class 8230 · Organization of conventions and trade shows / Subclass 82300 · Organization of conventions and trade shows",
  ),
  KeSicActivity(
      "829100",
      "Activities of collection agencies and credit bureaus",
      "Section N · Administrative and support service activities / Division 82 · Office administrative, office support and other business support activities / Group 829 · Business support service activities n.e.c / Class 8291 · Activities of collection agencies and credit bureaus / Subclass 82910 · Activities of collection agencies and credit bureaus",
  ),
  KeSicActivity(
      "829200",
      "Packaging activities",
      "Section N · Administrative and support service activities / Division 82 · Office administrative, office support and other business support activities / Group 829 · Business support service activities n.e.c / Class 8292 · Packaging activities / Subclass 82920 · Packaging activities",
  ),
  KeSicActivity(
      "829900",
      "Other business support service activities n.e.c",
      "Section N · Administrative and support service activities / Division 82 · Office administrative, office support and other business support activities / Group 829 · Business support service activities n.e.c / Class 8299 · Other business support service activities n.e.c / Subclass 82990 · Other business support service activities n.e.c",
  ),
  KeSicActivity(
      "841111",
      "National executive",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8411 · General public administration activities / Subclass 84111 · National executive and legislative administration",
  ),
  KeSicActivity(
      "841112",
      "Legislative administration",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8411 · General public administration activities / Subclass 84111 · National executive and legislative administration",
  ),
  KeSicActivity(
      "841121",
      "Public administration",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8411 · General public administration activities / Subclass 84112 · Public administration, county government",
  ),
  KeSicActivity(
      "841122",
      "County government",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8411 · General public administration activities / Subclass 84112 · Public administration, county government",
  ),
  KeSicActivity(
      "841130",
      "Public administration and supervision of fiscal affairs",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8411 · General public administration activities / Subclass 84113 · Public administration and supervision of fiscal affairs",
  ),
  KeSicActivity(
      "841140",
      "Ancillary services activities for the government as whole",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8411 · General public administration activities / Subclass 84114 · Ancillary services activities for the government as whole",
  ),
  KeSicActivity(
      "841190",
      "General public administration activities n.e.c",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8411 · General public administration activities / Subclass 84119 · General public administration activities n.e.c",
  ),
  KeSicActivity(
      "841210",
      "Regulatory agencies relating to health",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8412 · Regulation of the activities of providing health care, education, cultural services and other social services, excluding social security / Subclass 84121 · Regulatory agencies relating to health",
  ),
  KeSicActivity(
      "841220",
      "Regulatory agencies relating to education",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8412 · Regulation of the activities of providing health care, education, cultural services and other social services, excluding social security / Subclass 84122 · Regulatory agencies relating to education",
  ),
  KeSicActivity(
      "841290",
      "Regulatory agencies relating to other social services n.e.c. excluding social security",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8412 · Regulation of the activities of providing health care, education, cultural services and other social services, excluding social security / Subclass 84129 · Regulatory agencies relating to other social services n.e.c. excluding social security",
  ),
  KeSicActivity(
      "841301",
      "Public administration and regulation, including subsidy allocation, for different economic sectors:",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8413 · Regulation of and contribution to more efficient operation of businesses / Subclass 84130 · Regulation of and contribution to more efficient operation of businesses",
  ),
  KeSicActivity(
      "841302",
      "Administration of R&D policies and associated funds to improve economic performance",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8413 · Regulation of and contribution to more efficient operation of businesses / Subclass 84130 · Regulation of and contribution to more efficient operation of businesses",
  ),
  KeSicActivity(
      "841303",
      "Administration of general labour affairs e.g. COTU",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8413 · Regulation of and contribution to more efficient operation of businesses / Subclass 84130 · Regulation of and contribution to more efficient operation of businesses",
  ),
  KeSicActivity(
      "841304",
      "Implementation of regional development policy measures, e.g. to reduce unemployment( national employment authority)",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 841 · Administration of the State and the economic and social policy of the community / Class 8413 · Regulation of and contribution to more efficient operation of businesses / Subclass 84130 · Regulation of and contribution to more efficient operation of businesses",
  ),
  KeSicActivity(
      "842100",
      "Foreign affairs",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 842 · Provision of services to the community as a whole This group includes foreign affairs, defence and public order and safety activities / Class 8421 · Foreign affairs / Subclass 84210 · Foreign affairs",
  ),
  KeSicActivity(
      "842200",
      "Defence activities",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 842 · Provision of services to the community as a whole This group includes foreign affairs, defence and public order and safety activities / Class 8422 · Defence activities / Subclass 84220 · Defence activities",
  ),
  KeSicActivity(
      "842310",
      "Judiciary and related services",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 842 · Provision of services to the community as a whole This group includes foreign affairs, defence and public order and safety activities / Class 8423 · Public order and safety activities / Subclass 84231 · Judiciary and related services",
  ),
  KeSicActivity(
      "842320",
      "Police",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 842 · Provision of services to the community as a whole This group includes foreign affairs, defence and public order and safety activities / Class 8423 · Public order and safety activities / Subclass 84232 · Police",
  ),
  KeSicActivity(
      "842330",
      "Prisons",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 842 · Provision of services to the community as a whole This group includes foreign affairs, defence and public order and safety activities / Class 8423 · Public order and safety activities / Subclass 84233 · Prisons",
  ),
  KeSicActivity(
      "842390",
      "Public order and safety activities n.e.c",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 842 · Provision of services to the community as a whole This group includes foreign affairs, defence and public order and safety activities / Class 8423 · Public order and safety activities / Subclass 84239 · Public order and safety activities n.e.c",
  ),
  KeSicActivity(
      "843000",
      "Compulsory social security activities",
      "Section O · Public administration and defence; compulsory social security / Division 84 · Public administration and defence; compulsory s social security / Group 843 · Compulsory social security activities / Class 8430 · Compulsory social security activities / Subclass 84300 · Compulsory social security activities",
  ),
  KeSicActivity(
      "851010",
      "Pre-primary",
      "Section P · Education / Division 85 · Education / Group 851 · Pre-primary and primary education / Class 8510 · Pre-primary and primary education / Subclass 85101 · Pre-primary",
  ),
  KeSicActivity(
      "851020",
      "primary education",
      "Section P · Education / Division 85 · Education / Group 851 · Pre-primary and primary education / Class 8510 · Pre-primary and primary education / Subclass 85102 · primary education",
  ),
  KeSicActivity(
      "852100",
      "General secondary education",
      "Section P · Education / Division 85 · Education / Group 852 · Secondary education / Class 8521 · General secondary education / Subclass 85210 · General secondary education",
  ),
  KeSicActivity(
      "852210",
      "Secondary Vocational education",
      "Section P · Education / Division 85 · Education / Group 852 · Secondary education / Class 8522 · Technical and vocational secondary education / Subclass 85221 · Secondary Vocational education",
  ),
  KeSicActivity(
      "852220",
      "Technical education",
      "Section P · Education / Division 85 · Education / Group 852 · Secondary education / Class 8522 · Technical and vocational secondary education / Subclass 85222 · Technical education",
  ),
  KeSicActivity(
      "852230",
      "Vocational Education",
      "Section P · Education / Division 85 · Education / Group 852 · Secondary education / Class 8522 · Technical and vocational secondary education / Subclass 85223 · Vocational Education",
  ),
  KeSicActivity(
      "853010",
      "University education",
      "Section P · Education / Division 85 · Education / Group 853 · Higher education / Class 8530 · Higher education / Subclass 85301 · University education",
  ),
  KeSicActivity(
      "853020",
      "Polytechnics",
      "Section P · Education / Division 85 · Education / Group 853 · Higher education / Class 8530 · Higher education / Subclass 85302 · Polytechnics",
  ),
  KeSicActivity(
      "853030",
      "Commercial colleges offering higher education",
      "Section P · Education / Division 85 · Education / Group 853 · Higher education / Class 8530 · Higher education / Subclass 85303 · Commercial colleges offering higher education",
  ),
  KeSicActivity(
      "853040",
      "Other training Institutes",
      "Section P · Education / Division 85 · Education / Group 853 · Higher education / Class 8530 · Higher education / Subclass 85304 · Other training Institutes",
  ),
  KeSicActivity(
      "854100",
      "Sports and recreation education",
      "Section P · Education / Division 85 · Education / Group 854 · Other education / Class 8541 · Sports and recreation education / Subclass 85410 · Sports and recreation education",
  ),
  KeSicActivity(
      "854200",
      "Cultural education",
      "Section P · Education / Division 85 · Education / Group 854 · Other education / Class 8542 · Cultural education / Subclass 85420 · Cultural education",
  ),
  KeSicActivity(
      "854910",
      "Driving schools",
      "Section P · Education / Division 85 · Education / Group 854 · Other education / Class 8549 · Other education n.e.c / Subclass 85491 · Driving schools",
  ),
  KeSicActivity(
      "854920",
      "Flying schools",
      "Section P · Education / Division 85 · Education / Group 854 · Other education / Class 8549 · Other education n.e.c / Subclass 85492 · Flying schools",
  ),
  KeSicActivity(
      "854990",
      "Other education n.e.c",
      "Section P · Education / Division 85 · Education / Group 854 · Other education / Class 8549 · Other education n.e.c / Subclass 85499 · Other education n.e.c",
  ),
  KeSicActivity(
      "855000",
      "Educational support activities",
      "Section P · Education / Division 85 · Education / Group 855 · Educational support activities / Class 8550 · Educational support activities / Subclass 85500 · Educational support activities",
  ),
  KeSicActivity(
      "861000",
      "Hospital activities",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 861 · Hospital activities / Class 8610 · Hospital activities / Subclass 86100 · Hospital activities",
  ),
  KeSicActivity(
      "862010",
      "Medical practice activities",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 862 · Medical and dental practice activities / Class 8620 · Medical and dental practice activities / Subclass 86201 · Medical practice activities",
  ),
  KeSicActivity(
      "862020",
      "Dental practice activities",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 862 · Medical and dental practice activities / Class 8620 · Medical and dental practice activities / Subclass 86202 · Dental practice activities",
  ),
  KeSicActivity(
      "869010",
      "Medical laboratories",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 869 · Other human health activities / Class 8690 · Other human health activities / Subclass 86901 · Medical laboratories",
  ),
  KeSicActivity(
      "869020",
      "X-ray laboratories and other diagnostic imaging centres",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 869 · Other human health activities / Class 8690 · Other human health activities / Subclass 86902 · X-ray laboratories and other diagnostic imaging centres",
  ),
  KeSicActivity(
      "869030",
      "Home healthcare services",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 869 · Other human health activities / Class 8690 · Other human health activities / Subclass 86903 · Home healthcare services",
  ),
  KeSicActivity(
      "869040",
      "Activities of herbalists",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 869 · Other human health activities / Class 8690 · Other human health activities / Subclass 86904 · Activities of herbalists",
  ),
  KeSicActivity(
      "869050",
      "Activities of birth attendants",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 869 · Other human health activities / Class 8690 · Other human health activities / Subclass 86905 · Activities of birth attendants",
  ),
  KeSicActivity(
      "869090",
      "Other human health activities n.e.c",
      "Section Q · Human health and social work activities / Division 86 · Human health activities / Group 869 · Other human health activities / Class 8690 · Other human health activities / Subclass 86909 · Other human health activities n.e.c",
  ),
  KeSicActivity(
      "871000",
      "Residential nursing care facilities",
      "Section Q · Human health and social work activities / Division 87 · Residential care activities / Group 871 · Residential nursing care facilities / Class 8710 · Residential nursing care facilities / Subclass 87100 · Residential nursing care facilities",
  ),
  KeSicActivity(
      "872000",
      "Residential care activities for mental retardation, mental health and substance abuse",
      "Section Q · Human health and social work activities / Division 87 · Residential care activities / Group 872 · Residential care activities for mental retardation, mental health and substance abuse / Class 8720 · Residential care activities for mental retardation, mental health and substance abuse / Subclass 87200 · Residential care activities for mental retardation, mental health and substance abuse",
  ),
  KeSicActivity(
      "873000",
      "Residential care activities for the elderly and disabled",
      "Section Q · Human health and social work activities / Division 87 · Residential care activities / Group 873 · Residential care activities for the elderly and disabled / Class 8730 · Residential care activities for the elderly and disabled / Subclass 87300 · Residential care activities for the elderly and disabled",
  ),
  KeSicActivity(
      "879000",
      "Other residential care activities",
      "Section Q · Human health and social work activities / Division 87 · Residential care activities / Group 879 · Other residential care activities / Class 8790 · Other residential care activities / Subclass 87900 · Other residential care activities",
  ),
  KeSicActivity(
      "881000",
      "Social work activities without accommodation for the elderly and disabled",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 881 · Social work activities without accommodation for the elderly and disabled / Class 8810 · Social work activities without accommodation for the elderly and disabled / Subclass 88100 · Social work activities without accommodation for the elderly and disabled",
  ),
  KeSicActivity(
      "889100",
      "Child and youth service activities",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8891 · Child and youth service activities / Subclass 88910 · Child and youth service activities",
  ),
  KeSicActivity(
      "889200",
      "Other individual and family service activities",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8892 · Other individual and family service activities / Subclass 88920 · Other individual and family service activities",
  ),
  KeSicActivity(
      "889300",
      "Community food and housing service activities",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8893 · Community food and housing service activities / Subclass 88930 · Community food and housing service activities",
  ),
  KeSicActivity(
      "889400",
      "Temporary shelters",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8894 · Temporary shelters / Subclass 88940 · Temporary shelters",
  ),
  KeSicActivity(
      "889500",
      "Emergency and relief activities",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8895 · Emergency and relief activities / Subclass 88950 · Emergency and relief activities",
  ),
  KeSicActivity(
      "889600",
      "Vocational rehabilitation and habilitation activities",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8896 · Vocational rehabilitation and habilitation activities / Subclass 88960 · Vocational rehabilitation and habilitation activities",
  ),
  KeSicActivity(
      "889700",
      "Child day care service activities",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8897 · Child day care service activities / Subclass 88970 · Child day care service activities",
  ),
  KeSicActivity(
      "889800",
      "Charitable or other supporting activities aimed at social work",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8898 · Charitable or other supporting activities aimed at social work / Subclass 88980 · Charitable or other supporting activities aimed at social work",
  ),
  KeSicActivity(
      "889900",
      "Other social work activities without accommodation n.e.c",
      "Section Q · Human health and social work activities / Division 88 · Social work activities without accommodation / Group 889 · Other social work activities without accommodation / Class 8899 · Other social work activities without accommodation n.e.c / Subclass 88990 · Other social work activities without accommodation n.e.c",
  ),
  KeSicActivity(
      "900010",
      "Activities of sculptors, painters, cartoonists, engravers, etchers etc",
      "Section R · Arts, entertainment and recreation / Division 90 · Creative, arts and entertainment activities / Group 900 · Creative, arts and entertainment activities / Class 9000 · Creative, arts and entertainment activities / Subclass 90001 · Activities of sculptors, painters, cartoonists, engravers, etchers etc",
  ),
  KeSicActivity(
      "900020",
      "Production of live theatrical presentations, concerts and opera or dance productions and other stage productions",
      "Section R · Arts, entertainment and recreation / Division 90 · Creative, arts and entertainment activities / Group 900 · Creative, arts and entertainment activities / Class 9000 · Creative, arts and entertainment activities / Subclass 90002 · Production of live theatrical presentations, concerts and opera or dance productions and other stage productions",
  ),
  KeSicActivity(
      "900030",
      "Operation of concert and theatre halls and other arts facilities",
      "Section R · Arts, entertainment and recreation / Division 90 · Creative, arts and entertainment activities / Group 900 · Creative, arts and entertainment activities / Class 9000 · Creative, arts and entertainment activities / Subclass 90003 · Operation of concert and theatre halls and other arts facilities",
  ),
  KeSicActivity(
      "900040",
      "Activities of individual writers, for all subjects including fictional writing, technical writing etc",
      "Section R · Arts, entertainment and recreation / Division 90 · Creative, arts and entertainment activities / Group 900 · Creative, arts and entertainment activities / Class 9000 · Creative, arts and entertainment activities / Subclass 90004 · Activities of individual writers, for all subjects including fictional writing, technical writing etc",
  ),
  KeSicActivity(
      "900050",
      "Activities of independent journalists",
      "Section R · Arts, entertainment and recreation / Division 90 · Creative, arts and entertainment activities / Group 900 · Creative, arts and entertainment activities / Class 9000 · Creative, arts and entertainment activities / Subclass 90005 · Activities of independent journalists",
  ),
  KeSicActivity(
      "900060",
      "Restoring of works of art such as paintings etc",
      "Section R · Arts, entertainment and recreation / Division 90 · Creative, arts and entertainment activities / Group 900 · Creative, arts and entertainment activities / Class 9000 · Creative, arts and entertainment activities / Subclass 90006 · Restoring of works of art such as paintings etc",
  ),
  KeSicActivity(
      "900090",
      "Other creative arts and entertainment activities",
      "Section R · Arts, entertainment and recreation / Division 90 · Creative, arts and entertainment activities / Group 900 · Creative, arts and entertainment activities / Class 9000 · Creative, arts and entertainment activities / Subclass 90009 · Other creative arts and entertainment activities",
  ),
  KeSicActivity(
      "910101",
      "Library activities",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9101 · Library and archives activities / Subclass 91010 · Library and archives activities",
  ),
  KeSicActivity(
      "910102",
      "archives activities",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9101 · Library and archives activities / Subclass 91010 · Library and archives activities",
  ),
  KeSicActivity(
      "910210",
      "Museums activities",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9102 · Museums activities and operation of historical sites and buildings / Subclass 91021 · Museums activities",
  ),
  KeSicActivity(
      "910220",
      "Operation of historical sites and buildings",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9102 · Museums activities and operation of historical sites and buildings / Subclass 91022 · Operation of historical sites and buildings",
  ),
  KeSicActivity(
      "910230",
      "Art galleries",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9102 · Museums activities and operation of historical sites and buildings / Subclass 91023 · Art galleries",
  ),
  KeSicActivity(
      "910310",
      "Operation of botanical and zoological gardens, including animal orphanages, nature trail, arboretum",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9103 · Botanical and zoological gardens and nature reserves activities / Subclass 91031 · Operation of botanical and zoological gardens, including animal orphanages, nature trail, arboretum",
  ),
  KeSicActivity(
      "910321",
      "National Parks",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9103 · Botanical and zoological gardens and nature reserves activities / Subclass 91032 · Operation of nature reserves, including wildlife preservation, etc",
  ),
  KeSicActivity(
      "910322",
      "Game reserves",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9103 · Botanical and zoological gardens and nature reserves activities / Subclass 91032 · Operation of nature reserves, including wildlife preservation, etc",
  ),
  KeSicActivity(
      "910323",
      "Conservancies",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9103 · Botanical and zoological gardens and nature reserves activities / Subclass 91032 · Operation of nature reserves, including wildlife preservation, etc",
  ),
  KeSicActivity(
      "910324",
      "Marine parks",
      "Section R · Arts, entertainment and recreation / Division 91 · Libraries, archives, museums and other cultural activities / Group 910 · Libraries, archives, museums and other cultural activities / Class 9103 · Botanical and zoological gardens and nature reserves activities / Subclass 91032 · Operation of nature reserves, including wildlife preservation, etc",
  ),
  KeSicActivity(
      "920010",
      "sale of lottery tickets",
      "Section R · Arts, entertainment and recreation / Division 92 · Gambling and betting activities / Group 920 · Gambling and betting activities / Class 9200 · Gambling and betting activities / Subclass 92001 · sale of lottery tickets",
  ),
  KeSicActivity(
      "920020",
      "Casinos",
      "Section R · Arts, entertainment and recreation / Division 92 · Gambling and betting activities / Group 920 · Gambling and betting activities / Class 9200 · Gambling and betting activities / Subclass 92002 · Casinos",
  ),
  KeSicActivity(
      "920090",
      "Other gambling and betting activities",
      "Section R · Arts, entertainment and recreation / Division 92 · Gambling and betting activities / Group 920 · Gambling and betting activities / Class 9200 · Gambling and betting activities / Subclass 92009 · Other gambling and betting activities",
  ),
  KeSicActivity(
      "931100",
      "Operation of sports facilities",
      "Section R · Arts, entertainment and recreation / Division 93 · Sports activities and amusement and recreation activities / Group 931 · Sports activities / Class 9311 · Operation of sports facilities / Subclass 93110 · Operation of sports facilities",
  ),
  KeSicActivity(
      "931210",
      "Activities of football clubs",
      "Section R · Arts, entertainment and recreation / Division 93 · Sports activities and amusement and recreation activities / Group 931 · Sports activities / Class 9312 · Activities of sports clubs / Subclass 93121 · Activities of football clubs",
  ),
  KeSicActivity(
      "931290",
      "Activities of other sports clubs",
      "Section R · Arts, entertainment and recreation / Division 93 · Sports activities and amusement and recreation activities / Group 931 · Sports activities / Class 9312 · Activities of sports clubs / Subclass 93129 · Activities of other sports clubs",
  ),
  KeSicActivity(
      "931900",
      "Other sports activities",
      "Section R · Arts, entertainment and recreation / Division 93 · Sports activities and amusement and recreation activities / Group 931 · Sports activities / Class 9319 · Other sports activities / Subclass 93190 · Other sports activities",
  ),
  KeSicActivity(
      "932100",
      "Activities of amusement parks and theme parks",
      "Section R · Arts, entertainment and recreation / Division 93 · Sports activities and amusement and recreation activities / Group 932 · Other amusement and recreation activities / Class 9321 · Activities of amusement parks and theme parks / Subclass 93210 · Activities of amusement parks and theme parks",
  ),
  KeSicActivity(
      "932900",
      "Other amusement and recreation activities n.e.c",
      "Section R · Arts, entertainment and recreation / Division 93 · Sports activities and amusement and recreation activities / Group 932 · Other amusement and recreation activities / Class 9329 · Other amusement and recreation activities n.e.c / Subclass 93290 · Other amusement and recreation activities n.e.c",
  ),
  KeSicActivity(
      "941100",
      "Activities of business and employers membership organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 941 · Activities of business, employers and professional membership organizations / Class 9411 · Activities of business and employers membership organizations / Subclass 94110 · Activities of business and employers membership organizations",
  ),
  KeSicActivity(
      "941200",
      "Activities of professional membership organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 941 · Activities of business, employers and professional membership organizations / Class 9412 · Activities of professional membership organizations / Subclass 94120 · Activities of professional membership organizations",
  ),
  KeSicActivity(
      "942000",
      "Activities of trade unions",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 942 · Activities of trade unions / Class 9420 · Activities of trade unions / Subclass 94200 · Activities of trade unions",
  ),
  KeSicActivity(
      "949110",
      "Activities of Christian religious organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9491 · Activities of religious organizations / Subclass 94911 · Activities of Christian religious organizations",
  ),
  KeSicActivity(
      "949120",
      "Activities of Islamic religious organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9491 · Activities of religious organizations / Subclass 94912 · Activities of Islamic religious organizations",
  ),
  KeSicActivity(
      "949130",
      "Activities of Hindu religious organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9491 · Activities of religious organizations / Subclass 94913 · Activities of Hindu religious organizations",
  ),
  KeSicActivity(
      "949190",
      "Activities of other religious organizations n.e.c",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9491 · Activities of religious organizations / Subclass 94919 · Activities of other religious organizations n.e.c",
  ),
  KeSicActivity(
      "949200",
      "Activities of political organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9492 · Activities of political organizations / Subclass 94920 · Activities of political organizations",
  ),
  KeSicActivity(
      "949300",
      "Grantmaking and giving activities",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9493 · Grantmaking and giving activities / Subclass 94930 · Grantmaking and giving activities",
  ),
  KeSicActivity(
      "949400",
      "Activities of human rights organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9494 · Activities of human rights organizations / Subclass 94940 · Activities of human rights organizations",
  ),
  KeSicActivity(
      "949500",
      "Activities of environmental, conservation and wildlife organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9495 · Activities of environmental, conservation and wildlife organizations / Subclass 94950 · Activities of environmental, conservation and wildlife organizations",
  ),
  KeSicActivity(
      "949600",
      "Activities of other social advocacy organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9496 · Activities of other social advocacy organizations / Subclass 94960 · Activities of other social advocacy organizations",
  ),
  KeSicActivity(
      "949700",
      "Activities of cultural and recreational associations (other than sports or games)",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9497 · Activities of cultural and recreational associations (other than sports or games) / Subclass 94970 · Activities of cultural and recreational associations (other than sports or games)",
  ),
  KeSicActivity(
      "949800",
      "Activities of other civic and social organizations",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9498 · Activities of other civic and social organizations / Subclass 94980 · Activities of other civic and social organizations",
  ),
  KeSicActivity(
      "949900",
      "Activities of other membership organizations n.e.c",
      "Section S · Other service activities / Division 94 · Activities of membership organizations / Group 949 · Activities of other membership organizations / Class 9499 · Activities of other membership organizations n.e.c / Subclass 94990 · Activities of other membership organizations n.e.c",
  ),
  KeSicActivity(
      "951101",
      "Repair of computers",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 951 · Repair of computers and communication equipment / Class 9511 · Repair of computers and peripheral equipment / Subclass 95110 · Repair of computers and peripheral equipment",
  ),
  KeSicActivity(
      "951102",
      "Repair of ATMs",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 951 · Repair of computers and communication equipment / Class 9511 · Repair of computers and peripheral equipment / Subclass 95110 · Repair of computers and peripheral equipment",
  ),
  KeSicActivity(
      "951200",
      "Repair of communication equipment",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 951 · Repair of computers and communication equipment / Class 9512 · Repair of communication equipment / Subclass 95120 · Repair of communication equipment",
  ),
  KeSicActivity(
      "952100",
      "Repair of consumer electronics",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9521 · Repair of consumer electronics / Subclass 95210 · Repair of consumer electronics",
  ),
  KeSicActivity(
      "952210",
      "Repair and servicing of household appliances",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9522 · Repair of household appliances and home and garden equipment / Subclass 95221 · Repair and servicing of household appliances",
  ),
  KeSicActivity(
      "952220",
      "Repair and servicing of home and garden equipment",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9522 · Repair of household appliances and home and garden equipment / Subclass 95222 · Repair and servicing of home and garden equipment",
  ),
  KeSicActivity(
      "952300",
      "Repair of footwear and leather goods",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9523 · Repair of footwear and leather goods / Subclass 95230 · Repair of footwear and leather goods",
  ),
  KeSicActivity(
      "952400",
      "Repair of furniture and home furnishings",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9524 · Repair of furniture and home furnishings / Subclass 95240 · Repair of furniture and home furnishings",
  ),
  KeSicActivity(
      "952910",
      "Repair of bicycles",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9529 · Repair of other personal and household goods / Subclass 95291 · Repair of bicycles",
  ),
  KeSicActivity(
      "952920",
      "Repair and alteration of clothing",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9529 · Repair of other personal and household goods / Subclass 95292 · Repair and alteration of clothing",
  ),
  KeSicActivity(
      "952930",
      "Repair and alteration of jewellery",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9529 · Repair of other personal and household goods / Subclass 95293 · Repair and alteration of jewellery",
  ),
  KeSicActivity(
      "952940",
      "Repair of watches, clocks and their parts",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9529 · Repair of other personal and household goods / Subclass 95294 · Repair of watches, clocks and their parts",
  ),
  KeSicActivity(
      "952990",
      "Repair of other personal and household goods n.e.c",
      "Section S · Other service activities / Division 95 · Repair of computers and personal a and household goods / Group 952 · Repair of personal and household goods / Class 9529 · Repair of other personal and household goods / Subclass 95299 · Repair of other personal and household goods n.e.c",
  ),
  KeSicActivity(
      "960100",
      "Washing and (dry-) cleaning of textile and fur products",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9601 · Washing and (dry-) cleaning of textile and fur products / Subclass 96010 · Washing and (dry-) cleaning of textile and fur products",
  ),
  KeSicActivity(
      "960210",
      "Hairdressing and beauty salons",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9602 · Hairdressing and other beauty treatment / Subclass 96021 · Hairdressing and beauty salons",
  ),
  KeSicActivity(
      "960220",
      "Barber shops",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9602 · Hairdressing and other beauty treatment / Subclass 96022 · Barber shops",
  ),
  KeSicActivity(
      "960230",
      "Facial massage, manicure and pedicure services",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9602 · Hairdressing and other beauty treatment / Subclass 96023 · Facial massage, manicure and pedicure services",
  ),
  KeSicActivity(
      "960290",
      "Beauty and other personal care services n.e.c",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9602 · Hairdressing and other beauty treatment / Subclass 96029 · Beauty and other personal care services n.e.c",
  ),
  KeSicActivity(
      "960310",
      "Burialandincinerationofhumanoranimal corpses and related activities",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9603 · Funeral and related activities / Subclass 96031 · Burialandincinerationofhumanoranimal corpses and related activities",
  ),
  KeSicActivity(
      "960320",
      "Rental or sale of graves and maintenance of graves and mausoleums",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9603 · Funeral and related activities / Subclass 96032 · Rental or sale of graves and maintenance of graves and mausoleums",
  ),
  KeSicActivity(
      "960910",
      "Activities of sauna and steam baths, massage salons etc",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9609 · Other personal service activities n.e.c / Subclass 96091 · Activities of sauna and steam baths, massage salons etc",
  ),
  KeSicActivity(
      "960920",
      "Shoe shiners, porters, valet car parkers etc",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9609 · Other personal service activities n.e.c / Subclass 96092 · Shoe shiners, porters, valet car parkers etc",
  ),
  KeSicActivity(
      "960990",
      "Other personal service activities n.e.c.(e.g. baby sitters)",
      "Section S · Other service activities / Division 96 · Other personal service activities / Group 960 · Other personal service activities / Class 9609 · Other personal service activities n.e.c / Subclass 96099 · Other personal service activities n.e.c.(e.g. baby sitters)",
  ),
  KeSicActivity(
      "970000",
      "Activities of households as employers of domestic personnel",
      "Section T · Activities of households as employers and undifferentiated goods- and services-producing activities of households for own use / Division 97 · Activities of households as employers of domestic personnel / Group 970 · Activities of households as employers of domestic personnel / Class 9700 · Activities of households as employers of domestic personnel / Subclass 97000 · Activities of households as employers of domestic personnel",
  ),
  KeSicActivity(
      "981000",
      "Undifferentiated goods-producing activities of private households for own use",
      "Section T · Activities of households as employers and undifferentiated goods- and services-producing activities of households for own use / Division 98 · Undifferentiated goods- - a and services- producing activities of private households for own use / Group 981 · Undifferentiated goods-producing activities of private households for own use / Class 9810 · Undifferentiated goods-producing activities of private households for own use / Subclass 98100 · Undifferentiated goods-producing activities of private households for own use",
  ),
  KeSicActivity(
      "982000",
      "Undifferentiated service-producing activities of private households for own use",
      "Section T · Activities of households as employers and undifferentiated goods- and services-producing activities of households for own use / Division 98 · Undifferentiated goods- - a and services- producing activities of private households for own use / Group 982 · Undifferentiated service-producing activities of private households for own use / Class 9820 · Undifferentiated service-producing activities of private households for own use / Subclass 98200 · Undifferentiated service-producing activities of private households for own use",
  ),
  KeSicActivity(
      "990010",
      "Activities of international organizations",
      "Section U · Activities of extraterritorial organizations and bodies / Division 99 · Activities of extraterritorial organizations and bodies / Group 990 · Activities of extraterritorial organizations and bodies / Class 9900 · Activities of extraterritorial organizations and bodies / Subclass 99001 · Activities of international organizations",
  ),
  KeSicActivity(
      "990020",
      "Activities of diplomatic and consular missions when being determined by the country of their location rather than by the country they represent",
      "Section U · Activities of extraterritorial organizations and bodies / Division 99 · Activities of extraterritorial organizations and bodies / Group 990 · Activities of extraterritorial organizations and bodies / Class 9900 · Activities of extraterritorial organizations and bodies / Subclass 99002 · Activities of diplomatic and consular missions when being determined by the country of their location rather than by the country they represent",
  ),
 ];

/// Only codes present in this versioned official reference are verified.
bool isCachedKesicCode(String code) =>
    kesicActivities.any((activity) => activity.code == code);
