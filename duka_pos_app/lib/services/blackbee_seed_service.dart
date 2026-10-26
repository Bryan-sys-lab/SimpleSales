/// The BlackBee workbook is a catalogue reference only.
///
/// Keep names, not its historical prices, stock counts, barcodes, or sales.
/// Prices are collected interactively in the normal import-completion sheet.
class BlackbeeSeedService {
  const BlackbeeSeedService._();

  static const List<String> productNames = <String>[
    'Absolute Vodka', 'All Season', 'Baileys', 'Balck and White',
    'Ballantines', 'Best Gin', 'Best Vodka', 'Best whisky', 'Bond 7',
    'Captain Morgan', 'Chrome Gin', 'Chrome Vodka', 'County', 'Famouse Gouse',
    'General meakins', 'Gilbys', 'Gordons', 'Grants', 'Hampton', 'Hennesy',
    'Hunters Choice', 'Jack Daniels', 'Jamesom', 'Jameson Black Barrel',
    'Jegermifter', 'JW Black Label', 'JW Double Black', 'JW Red Label',
    'Kane Extra', 'Kenya Cane Ginger', 'Kenya Cane Pineapple',
    'Kenya Cane Smooth', 'Kenya King', 'Kibao Vodka', 'Konyagi', 'Martel',
    'Richot', 'Robertson', 'Rosa', 'S.Walker', 'Sminoff Vodka', 'Tripple Ace',
    'V and A', 'VAT 69', 'Viceroy', 'William Lawsons', 'Black Label',
    'Caribia GIN', 'Double Black', 'Gordons 375ml', 'Jack Daniels 1ltr',
    'Red Label', 'Royal', 'All Seasons', 'Black and White', 'Famouse G',
    'Gilbys Gin', 'Jameson', 'Kenya Cane', 'Red label', 'Robeertson',
    'William Lawsson', 'Best Cream', 'Best Whiskey', 'Balck Label', 'Blue Ice',
    'Caribia', 'Chrome Lemon', 'General Meakins', 'Just Right',
    'Kenya Cane Citrus', 'Kibao Gin', 'Kienyeji', 'Legend', 'Napoleone',
    'Origin', 'People', 'Smart', 'Sweet Berry', 'V n A', 'White Perl',
    'Allsops', 'Balozi', 'Banana', 'Black Ice', 'Guiness', 'Guiness Smooth',
    'Heineken', 'Kingfisher', 'K.O Cider', 'Pilsner', 'Savanna Cider', 'Snapp',
    'Tusker Cider', 'Tusker Larger', 'Tusker Lite', 'Tusker Malt', 'White Cap',
    'Manyatta', 'Balck Ice', 'Casabuena', 'Caprice', 'Faxe', 'Guarana', 'Lion',
    'O.K 12', 'O.KJ 16', 'Smirnoff punch', 'Smirnoff punch can', 'Afia',
    'Bubble Up', 'Delmonte', 'Four cousins', 'Lemonade', 'Lime Juice',
    'Minute Maid', 'Monster', 'Planet', 'Poer Play', 'Predetor', 'Red bull',
    'Simba', 'Soda 1 ltr', 'Soda 500ml', 'Soda 300ml', 'Tunda', 'Water 1 ltr',
    'Water 500ml', 'Water 1.5Ltr', '4th Street',
  ];
}
