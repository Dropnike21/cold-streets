import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';

class CityMapView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;

  // 🚨 ADDED: The map now accepts the same navigation function as the drawer!
  final Function(int)? onNavigate;

  const CityMapView({super.key, required this.userData, required this.onBack, this.onNavigate});

  @override
  State<CityMapView> createState() => _CityMapViewState();
}

class _CityMapViewState extends State<CityMapView> {
  static const Color cNeon = Color(0xFF39FF14);
  static const Color cBlack = Color(0xFF121212);
  static const Color cDark = Color(0xFF1E1E1E);
  static const Color cGold = Color(0xFFFFD700);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  // 🚨 BUILDING TO SCREEN ROUTER
  // This translates the Name of the Building you tap on the map into the Index number of the screen!
  final Map<String, int> buildingNavigationIndices = {
    "Gym": 5,
    "Item Market": 6,
    "City Hall": 8,
    "Info-Broker": 13,
    "Jail": 14,
    "Hospital": 15,
    "University": 16,
    "Bank": 17,
    "Real Estate": 18,
    "Casino": 20,
    // You can add "Auction House" and others here as you build those screens!
  };

  final Map<String, List<String>> syndicateDistricts = {
    "Deep Gate": ["Block 250", "Block 247", "Block 249", "Block 248", "Block 251", "Block 69", "Block 81", "Block 80", "Block 79", "Block 78", "Block 68", "Block 121", "Block 124", "Block 125", "Block 127", "Block 123", "Block 70", "Block 120", "Block 119", "Block 118", "Block 126", "Block 130", "Block 129", "Block 128", "Block 48", "Block 49", "greens 892"],
    "Wine Docks": ["Block 176", "Block 177", "Block 179", "Block 178", "Block 182", "Block 180", "Block 192", "Block 181", "Block 193", "Block 195", "Block 92", "Block 91", "Block 90", "Block 89", "Block 189", "Block 190", "Block 191", "Block 194", "Block 183", "Block 184", "Block 186", "Block 185", "Block 187", "Block 188"],
    "Northern harbour": ["Block 347", "Block 346", "Block 339", "Block 340", "Block 342", "Block 341", "Block 343", "Block 345", "Block 344", "Block 353", "Block 352", "Block 350", "Block 348", "Block 351", "Block 349", "Block 368", "Block 360", "Block 359", "Block 362", "Block 363", "Block 361", "Block 367", "Block 366", "Block 378", "Block 377"],
    "Southern harbour": ["Block 527", "Block 526", "Block 525", "Block 523", "Block 522", "Block 521", "Block 518", "Block 514", "Block 513", "Block 510", "Block 512", "Block 511", "Block 517", "Block 516", "Block 515", "Block 524", "Block 520", "Block 519", "Block 283", "Block 284", "Block 287", "Block 285", "Block 282", "Block 289", "Block 288", "Block 290"],
    "South-East Slums": ["Block 552", "Block 620", "Block 550", "Block 551", "Block 549", "Block 548", "Block 535", "Block 534", "Block 532", "Block 536", "Block 537", "Block 539", "Block 540", "Block 538", "Block 530", "Block 533", "Block 547", "Block 531", "Block 541", "Block 542", "Block 543", "Block 544", "Block 529", "Block 528", "Block 556", "Block 557", "Block 560", "Block 545", "Block 553", "Block 546", "Block 555", "Block 558", "Block 559", "Block 554", "Block 617", "Block 618", "Block 619", "Block 607", "Block 606", "Block 608", "Block 609", "Block 610", "Block 611", "Block 616", "Block 615", "Block 613", "Block 612", "Block 614", "Block 601", "Block 595", "Block 596", "Block 621", "Block 622", "Block 623", "Block 624", "Block 625", "Block 635", "Block 636", "Block 634", "Block 630", "Block 633", "Block 631", "Block 632", "Block 584", "Block 585", "Block 587", "Block 588", "Block 591", "Block 592", "Block 589", "Block 586", "Block 598", "Block 599", "Block 600", "Block 597", "Block 594", "Block 604", "Block 603", "Block 590", "Block 593", "Block 396", "Block 397", "Block 395", "Block 398", "Block 392", "Block 393", "Block 605", "Block 602"],
    "South-West Slums": ["Block 458", "Block 456", "Block 457", "Block 459", "Block 460", "Block 680", "Block 681", "Block 682", "Block 688", "Block 689", "Block 690", "Block 466", "Block 467", "Block 686", "Block 687", "Block 685", "Block 683", "Block 468", "Block 684", "Block 465", "Block 463", "Block 462", "Block 461", "Block 464", "Block 475", "Block 476", "Block 472", "Block 471", "Block 474", "Block 473", "Block 470", "Block 469", "Block 694", "Block 695", "Block 696", "Block 692", "Block 691", "Block 495", "Block 494", "Block 488", "Block 487", "Block 490", "Block 489", "Block 492", "Block 493", "Block 491", "Block 702", "Block 701", "Block 703", "Block 482", "Block 481", "Block 480", "Block 698", "Block 697", "Block 699", "Block 700", "Block 485", "Block 484", "Block 479", "Block 478", "Block 477", "Block 483", "Block 486", "Block 497", "Block 501", "Block 500", "Block 498", "Block 499", "Block 496", "Block 507", "Block 504", "Block 503", "Block 502", "Block 506", "Block 505", "Block 508", "Block 509", "Block 693"],
    "South Slums": ["Block 627", "Block 626", "Block 628", "Block 629", "Block 655", "Block 658", "Block 657", "Block 654", "Block 864", "Block 863", "Block 862", "Block 858", "Block 859", "Block 861", "Block 857", "Block 856", "Block 883", "Block 865", "Block 882", "Block 649", "Block 650", "Block 653", "Block 652", "Block 881", "Block 880", "Block 809", "Block 811", "Block 820", "Block 821", "Block 860", "Block 822", "Block 810", "Block 808", "Block 878", "Block 879", "Block 651", "Block 876", "Block 877", "Block 875", "Block 807", "Block 806", "Block 805", "Block 819", "Block 817", "Block 818", "Block 825", "Block 824", "Block 823", "Block 812", "Block 815", "Block 813", "Block 831", "Block 832", "Block 829", "Block 826", "Block 874", "Block 873", "Block 816", "Block 814", "Block 830", "Block 828", "Block 827", "Block 870", "Block 871", "Block 842", "Block 872", "Block 843", "Block 839", "Block 835", "Block 833", "Block 836", "Block 840", "Block 841", "Block 844", "Block 845", "Block 868", "Block 869", "Block 867", "Block 389", "Block 390", "Block 391", "Block 866", "Block 853", "Block 852", "Block 851", "Block 850", "Block 855", "Block 854", "Block 849", "Block 847", "Block 846", "Block 848", "Block 838", "Block 837", "Block 656"],
    "Grimrise Gate": ["Block 64", "Block 65", "Block 60", "Block 59", "Block 57", "Block 56", "Block 58", "Block 61", "Block 63", "Block 66", "Block 62", "Block 72", "Block 44", "Block 71", "Block 74", "Block 73", "Block 76", "Block 75", "Block 77", "Block 67", "Block 131", "Block 134", "Block 132", "Block 133", "Block 137", "Block 135", "Block 136", "Block 45", "Block 46", "Block 55", "Block 47", "Block 53", "Block 54", "Block 52", "Block 50", "Block 51"],
    "Milkspring": ["Block 797", "Block 791", "Block 793", "Block 792", "Block 794", "Block 798", "Block 796", "Block 795", "Block 799", "Block 800", "Block 801", "Block 803", "Block 802", "Block 887", "Block 888", "Block 750", "Block 751", "Block 752", "Block 753", "Block 754", "Block 419", "Block 417", "Block 418", "Block 416", "Block 415", "Block 412", "Block 413", "Block 414", "Block 420", "Block 405", "Block 406", "Block 407", "Block 409", "Block 411", "Block 399", "Block 402", "Block 400", "Block 401", "Block 410", "Block 403", "Block 404", "Block 408"],
    "Eversoul Gate": ["Block 332", "Block 330", "Block 331", "Block 327", "Block 329", "Block 328", "Block 326", "Block 324", "Block 323", "Block 322", "Block 265", "Block 263", "Block 264", "Block 260", "Block 266", "Block 268", "Block 267", "Block 110", "Block 111", "Block 112", "Block 113", "Block 107", "Block 109", "Block 102", "Block 108", "Block 103", "Block 106", "Block 105", "Block 259", "Block 262", "Block 261"],
    "Bright Borough": ["Block 733", "Block 730", "Block 731", "Block 736", "Block 735", "Block 734", "Block 729", "Block 749", "Block 732", "Block 748", "Block 747", "Block 743", "Block 742", "Block 741", "Block 746", "Block 744", "Block 745", "Block 739", "Block 738", "Block 740", "Block 737", "Block 726", "Block 727", "Block 728", "Block 724", "Block 725", "Block 723", "Block 721", "Block 719", "Block 722", "Block 720", "Block 714", "Block 715", "Block 718", "Block 717", "Block 716", "Block 712", "Block 713"],
    "Red Light": ["Block 319", "Block 318", "Block 311", "Block 315", "Block 312", "Block 313", "Block 310", "Block 314", "Block 317", "Block 305", "Block 306", "Block 308", "Block 309", "Block 307", "Block 321", "Block 320", "Block 316", "Block 242", "Block 243", "Block 245", "Block 244", "Block 281", "Block 280", "Block 241", "Block 278", "Block 279", "Block 277", "Block 276", "Block 275", "Block 274"],
    "Iron Docks": ["Block 167", "Block 169", "Block 168", "Block 163", "Block 164", "Block 162", "Block 165", "Block 174", "Block 172", "Block 175", "Block 173", "Block 171", "Block 170", "Block 2", "Block 10", "Block 11", "Block 9", "Block 8", "Block 6", "Block 5", "Block 4", "Block 7", "Block 3"],
    "Merchants Town": ["Block 217", "Block 218", "Block 219", "Block 221", "Block 224", "Block 220", "Block 225", "Block 222", "Block 223", "Block 226", "Block 227", "Block 234", "Block 235", "Block 228", "Block 236", "Block 237", "Block 230", "Block 229", "Block 231", "Block 232", "Block 239", "Block 240", "Block 238", "Block 233", "Block 117", "Block 114", "Block 116", "Block 143", "Block 142", "Block 144", "Block 141", "Block 140", "Block 139", "Block 147", "Block 146", "Block 145", "Block 159", "Block 160", "Block 161", "Block 157", "Block 158", "Block 154", "Block 156", "Block 155", "Block 151", "Block 152", "Block 149", "Block 153", "Block 150", "Block 148", "greens 893", "greens 891"],
    "West Slums": ["Block 432", "Block 437", "Block 436", "Block 427", "Block 428", "Block 426", "Block 422", "Block 421", "Block 448", "Block 449", "Block 446", "Block 447", "Block 450", "Block 451", "Block 440", "Block 640", "Block 639", "Block 637", "Block 648", "Block 646", "Block 647", "Block 638", "Block 643", "Block 644", "Block 641", "Block 642", "Block 645", "Block 580", "Block 579", "Block 441", "Block 439", "Block 576", "Block 578", "Block 577", "Block 572", "Block 438", "Block 455", "Block 453", "Block 442", "Block 444", "Block 424", "Block 425", "Block 434", "Block 435", "Block 433", "Block 431", "Block 430", "Block 429", "Block 561", "Block 563", "Block 445", "Block 452", "Block 454", "Block 562", "Block 575", "Block 574", "Block 573", "Block 570", "Block 566", "Block 567", "Block 564", "Block 565", "Block 571", "Block 569", "Block 568", "Block 581", "Block 582", "Block 704", "Block 705", "Block 706", "Block 708", "Block 707"],
    "Smogworks": ["Block 355", "Block 356", "Block 357", "Block 374", "Block 379", "Block 376", "Block 777", "Block 790", "Block 780", "Block 779", "Block 358", "Block 354", "Block 785", "Block 786", "Block 778", "Block 774", "Block 773", "Block 775", "Block 787", "Block 789", "Block 788", "Block 783", "Block 782", "Block 781", "Block 784", "Block 755", "Block 756", "Block 757", "Block 760", "Block 772", "Block 768", "Block 765", "Block 766", "Block 767", "Block 770", "Block 776", "Block 761", "Block 771", "Block 769", "Block 763", "Block 759", "Block 758", "Block 764"],
    "outskirts field": ["fields 894", "fields 895", "fields 896", "fields 918", "fields 915", "fields 914", "fields 916", "fields 917", "fields 931", "fields 936", "fields 939", "fields 935", "fields 940", "fields 934", "fields 938", "fields 937", "fields 933", "fields 897", "fields 898", "fields 905", "fields 903", "fields 906", "fields 904", "fields 899", "fields 900", "fields 901", "fields 902", "fields 912", "fields 913", "fields 911", "fields 919", "fields 910", "fields 920", "fields 921", "fields 925", "fields 909", "fields 908", "fields 907", "fields 929", "fields 928", "fields 927", "fields 926", "fields 924", "fields 922", "fields 923", "Block 709", "Block 711", "Block 583", "Block 885", "Block 886", "Block 804", "Block 710", "Block 884"],
    "Blackwater Basin": ["Block 334", "Block 335", "Block 333", "Block 388", "Block 387", "Block 386", "Block 337", "Block 336", "Block 385", "Block 384", "Block 338", "Block 383", "Block 381", "Block 365", "Block 382", "Block 380", "Block 364", "Block 370", "Block 369", "Block 371", "Block 372", "Block 373", "Block 375", "Block 675", "Block 673", "Block 674", "Block 672", "Block 677", "Block 676", "Block 678", "Block 671", "Block 660", "Block 661", "Block 662", "Block 659", "Block 667", "Block 669", "Block 668", "Block 664", "Block 665", "Block 670", "Block 666"],
    "Highrise": ["Block 30", "Block 29", "Block 32", "Block 31", "Block 35", "Block 34", "Block 33", "Block 36", "Block 28", "Block 12", "Block 14", "Block 18", "Block 37", "Block 17", "Block 16", "Block 15", "Block 13", "Block 39", "Block 40", "Block 41", "Block 38", "Block 270", "Block 271", "Block 269", "Block 272", "Block 273", "Block 42"],
    "Scraptown": ["Block 101", "Block 95", "Block 87", "Block 88", "Block 96", "Block 94", "Block 93", "Block 97", "Block 100", "Block 99", "Block 98"],
    "Sentinel": ["Block 292", "Block 291", "Block 294", "Block 293", "Block 295", "Block 298", "Block 299", "Block 303", "Block 300", "Block 297", "Block 301", "Block 304", "Block 302", "Block 296", "Block 207", "Block 206", "Block 252", "Block 254", "Block 253", "Block 255", "Block 257", "Block 256", "Block 258", "Block 203", "Block 204", "Block 202", "Block 205", "Block 210", "Block 208", "Block 216", "Block 212", "Block 211", "Block 214", "Block 213", "Block 215", "Block 83", "Block 85", "Block 209", "Block 200", "Block 201", "Block 199", "Block 197", "Block 196", "Block 22", "Block 21", "Block 19", "Block 27", "Block 26", "Block 25", "Block 23", "Block 24", "Block 20", "Block 82", "Block 84", "Block 86", "Block 198"],
    "Gym": ["Block 394"],
    "Item Market": ["Block 1"],
    "Player Bazaar": ["squares 890"],
    "City Hall": ["Block 138"],
    "Jail": ["Block 679"],
    "Hospital": ["Block 115"],
    "Docks": ["Block 166"],
    "Casino": ["Block 122"],
    "Bank": ["Block 43"],
    "Info-Broker": ["Block 246"],
    "Real Estate": ["Block 104"],
    "University": ["Block 663"],
    "Stock Market": ["Block 762"],
    "Auction House": ["Block 325"],
    "Underground Munitions": ["Block 834"],
    "The Pharmacy": ["Block 286"],
    "The Chop Shop": ["Block 423"],
    "The Street Circuit": ["Block 443"],
  };

  Map<String, String> blockToDistrictMap = {};
  List<Map<String, dynamic>> interactiveDistricts = [];
  LatLngBounds? imageBounds;
  LatLng? mapCenter;
  bool isLoading = true;
  String errorMessage = "";

  String? selectedBlockId;

  bool showMapArt = true;
  bool showDistrictZoning = false;
  bool isMenuOpen = false;
  double currentZoom = -1.0;

  @override
  void initState() {
    super.initState();

    syndicateDistricts.forEach((districtName, blocks) {
      for (var block in blocks) {
        blockToDistrictMap[block] = districtName;
      }
    });

    _loadWatabouData();
  }

  Future<void> _loadWatabouData() async {
    try {
      String jsonString = await rootBundle.loadString('assets/city_blocks.json');
      Map<String, dynamic> geoJson = jsonDecode(jsonString);

      List<Map<String, dynamic>> tempDistricts = [];
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      const double scaleFactor = 200.0;
      int blockCounter = 1;

      for (var item in geoJson['features']) {
        try {
          String type = item['type']?.toString() ?? '';
          String rawId = item['id']?.toString() ?? item['properties']?['id']?.toString() ?? 'unknown';

          if (rawId == 'values') continue;

          List<dynamic> polygonsData = [];
          if (type == 'Polygon' && item['coordinates'] != null) polygonsData.add(item['coordinates'][0]);
          else if (type == 'MultiPolygon' && item['coordinates'] != null) for (var poly in item['coordinates']) polygonsData.add(poly[0]);
          else if (type == 'GeometryCollection' && item['geometries'] != null) {
            for (var geom in item['geometries']) {
              if (geom['type'] == 'Polygon' && geom['coordinates'] != null) polygonsData.add(geom['coordinates'][0]);
              else if (geom['type'] == 'MultiPolygon' && geom['coordinates'] != null) for (var poly in geom['coordinates']) polygonsData.add(poly[0]);
            }
          } else if (type == 'Feature' && item['geometry'] != null) {
            String geoType = item['geometry']['type'];
            if (geoType == 'Polygon') polygonsData.add(item['geometry']['coordinates'][0]);
            else if (geoType == 'MultiPolygon') for (var poly in item['geometry']['coordinates']) polygonsData.add(poly[0]);
          }

          for (var rawCoords in polygonsData) {
            List<LatLng> polygonPoints = [];

            double sumX = 0, sumY = 0;
            for (var point in rawCoords) {
              sumX += (point[0] as num).toDouble();
              sumY += (point[1] as num).toDouble();
            }
            double cx = sumX / rawCoords.length;
            double cy = sumY / rawCoords.length;

            double expandFactor = (rawId != 'earth') ? 1.03 : 1.0;

            for (var point in rawCoords) {
              double px = (point[0] as num).toDouble();
              double py = (point[1] as num).toDouble();

              double newX = cx + (px - cx) * expandFactor;
              double newY = cy + (py - cy) * expandFactor;

              double x = newX / scaleFactor;
              double y = newY / scaleFactor;

              if (rawId == 'earth') {
                if (x < minX) minX = x; if (x > maxX) maxX = x;
                if (y < minY) minY = y; if (y > maxY) maxY = y;
              }
              polygonPoints.add(LatLng(y, x));
            }

            if (rawId != 'earth' && rawId != 'water' && rawId != 'river' && rawId != 'rivers' && rawId != 'roads' && rawId != 'planks' && rawId != 'walls' && rawId != 'towers') {
              if (polygonPoints.isNotEmpty) {
                String blockId = (rawId == 'buildings' || rawId == 'unknown') ? 'Block $blockCounter' : '$rawId $blockCounter';

                if (blockToDistrictMap.containsKey(blockId)) {
                  tempDistricts.add({'id': blockId, 'points': polygonPoints});
                }
                blockCounter++;
              }
            }
          }
        } catch (e) { continue; }
      }

      if (minX == double.infinity) throw Exception("Could not find boundaries.");

      setState(() {
        interactiveDistricts = tempDistricts;
        imageBounds = LatLngBounds(LatLng(minY + 13.80, minX + 17.80), LatLng(maxY - 15.20, maxX - 21.60));
        mapCenter = LatLng((imageBounds!.south + imageBounds!.north) / 2, (imageBounds!.west + imageBounds!.east) / 2);
        isLoading = false;
      });

    } catch (e) {
      setState(() { errorMessage = e.toString(); isLoading = false; });
    }
  }

  void _searchAndZoomToBlock(String query) {
    if (query.isEmpty) return;
    var foundBlock = interactiveDistricts.where((d) => d['id'].toString().toLowerCase() == query.toLowerCase()).firstOrNull;
    if (foundBlock != null) {
      List<LatLng> pts = foundBlock['points'];
      double latSum = 0; double lngSum = 0;
      for (var p in pts) { latSum += p.latitude; lngSum += p.longitude; }
      LatLng centerPoint = LatLng(latSum / pts.length, lngSum / pts.length);

      _mapController.move(centerPoint, 1.2);
      setState(() {
        selectedBlockId = foundBlock['id'];
        currentZoom = 1.2;
        FocusScope.of(context).unfocus();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not find '$query'", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
    }
  }

  void _handleMapTap(TapPosition tapPosition, LatLng latLng) {
    String? tappedId;
    for (var block in interactiveDistricts) {
      if (_isPointInPolygon(latLng, block['points'])) { tappedId = block['id']; break; }
    }
    setState(() => selectedBlockId = tappedId);
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool isInside = false;
    int i, j = polygon.length - 1;
    for (i = 0; i < polygon.length; i++) {
      double xi = polygon[i].longitude, yi = polygon[i].latitude;
      double xj = polygon[j].longitude, yj = polygon[j].latitude;
      bool intersect = ((yi > point.latitude) != (yj > point.latitude)) && (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersect) isInside = !isInside;
      j = i;
    }
    return isInside;
  }

  Color _getDistrictColor(String districtName) {
    int hash = districtName.hashCode;
    int r = (hash & 0xFF0000) >> 16;
    int g = (hash & 0x00FF00) >> 8;
    int b = hash & 0x0000FF;
    return Color.fromARGB(255, r, g, b).withValues(alpha: 0.6);
  }

  Widget _buildTacticalModal() {
    if (selectedBlockId == null) return const SizedBox.shrink();

    String parentDistrict = blockToDistrictMap[selectedBlockId!] ?? "UNZONED SECTOR";
    bool isSpecialBuilding = syndicateDistricts[parentDistrict]?.length == 1;
    Color themeColor = isSpecialBuilding ? cGold : cNeon;

    return Container(
      width: 320, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cDark, border: Border.all(color: themeColor, width: 2), borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: themeColor.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5)]),
      child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(
                        isSpecialBuilding ? parentDistrict.toUpperCase() : "TERRITORY:\n${selectedBlockId!.toUpperCase()}",
                        style: TextStyle(color: themeColor, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)
                    )
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() => selectedBlockId = null))
              ]
          ),

          if (!isSpecialBuilding)
            Text("DISTRICT: ${parentDistrict.toUpperCase()}", style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),

          const Divider(color: Color(0xFF333333), height: 24),

          if (isSpecialBuilding) ...[
            const Text("City Infrastructure", style: TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic)),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity, height: 45,
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: cGold.withValues(alpha: 0.1), side: const BorderSide(color: cGold)),
                    onPressed: () {
                      // 🚨 THE CONNECTION: Triggers the navigation index if we mapped it!
                      int? targetIndex = buildingNavigationIndices[parentDistrict];

                      if (targetIndex != null && widget.onNavigate != null) {
                        widget.onNavigate!(targetIndex);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$parentDistrict is still under construction."), backgroundColor: Colors.redAccent));
                      }
                    },
                    child: Text("ENTER ${parentDistrict.toUpperCase()}", style: const TextStyle(color: cGold, fontWeight: FontWeight.bold, letterSpacing: 1))
                )
            )
          ] else ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text("DAILY UPKEEP:", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)), Text("\$5,000", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text("INFLUENCE YIELD:", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)), Text("+10 IP / Day", style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity, height: 45,
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.redAccent)),
                    onPressed: () {},
                    child: const Text("LAUNCH ASSAULT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1))
                )
            )
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(backgroundColor: cBlack, body: Center(child: CircularProgressIndicator(color: cNeon)));

    LatLngBounds tightConstraint = LatLngBounds(
      LatLng(imageBounds!.south - 0.1, imageBounds!.west - 0.1),
      LatLng(imageBounds!.north + 0.1, imageBounds!.east + 0.1),
    );

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              crs: const CrsSimple(),
              initialCenter: mapCenter!,
              initialZoom: -2.0,
              minZoom: -5.0,
              maxZoom: 4.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.doubleTapZoom & ~InteractiveFlag.rotate),
              cameraConstraint: CameraConstraint.contain(bounds: tightConstraint),
              onTap: _handleMapTap,

              onPositionChanged: (MapCamera camera, bool hasGesture) {
                if (hasGesture && isMenuOpen) {
                  setState(() => isMenuOpen = false);
                }
                currentZoom = camera.zoom;
              },
            ),
            children: [
              if (showMapArt) OverlayImageLayer(overlayImages: [OverlayImage(bounds: imageBounds!, imageProvider: const AssetImage('assets/detailed_cmbg.png'))]),

              PolygonLayer(polygons: interactiveDistricts.map((block) {
                bool isSel = block['id'] == selectedBlockId;
                String parentDistrict = blockToDistrictMap[block['id']] ?? "UNZONED";
                bool isSpecialBuilding = syndicateDistricts[parentDistrict]?.length == 1;

                Color fillCol = Colors.transparent;
                Color borderCol = Colors.transparent;
                double strokeWidth = 1.0;

                if (isSel) {
                  fillCol = (isSpecialBuilding ? cGold : cNeon).withValues(alpha: 0.4);
                  borderCol = Colors.white;
                  strokeWidth = 3.0;
                }
                else if (showDistrictZoning) {
                  fillCol = isSpecialBuilding ? cGold.withValues(alpha: 0.6) : _getDistrictColor(parentDistrict);
                  borderCol = Colors.black45;
                }
                else {
                  fillCol = showMapArt ? Colors.transparent : Colors.grey[850]!;
                  borderCol = showMapArt ? Colors.transparent : Colors.grey[700]!;

                  if (isSpecialBuilding && showMapArt) {
                    borderCol = cGold.withValues(alpha: 0.8);
                    strokeWidth = 2.0;
                  }
                }

                return Polygon(
                  points: block['points'],
                  color: fillCol,
                  borderColor: borderCol,
                  borderStrokeWidth: strokeWidth,
                );
              }).toList()),
            ],
          ),

          Positioned(
              top: 40, left: 20,
              child: Container(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                child: IconButton(icon: const Icon(Icons.arrow_back, color: cNeon), onPressed: widget.onBack),
              )
          ),

          Positioned(
            top: 40, right: 20,
            left: isDesktop ? null : 70,
            width: isDesktop ? (screenWidth * 0.25).clamp(250.0, 350.0) : null,
            child: Container(
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8), border: Border.all(color: cNeon)),
              child: Row(children: [
                const Padding(padding: EdgeInsets.all(12.0), child: Icon(Icons.search, color: cNeon)),
                Expanded(child: TextField(controller: _searchController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Search block...", hintStyle: TextStyle(color: Colors.white30), border: InputBorder.none), onSubmitted: _searchAndZoomToBlock)),
                IconButton(icon: const Icon(Icons.gps_fixed, color: cNeon), onPressed: () => _searchAndZoomToBlock(_searchController.text))
              ]),
            ),
          ),

          Positioned(
              top: 100, right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    heroTag: "hud_menu_btn",
                    mini: true,
                    backgroundColor: cDark,
                    shape: RoundedRectangleBorder(side: const BorderSide(color: cNeon), borderRadius: BorderRadius.circular(8)),
                    onPressed: () => setState(() => isMenuOpen = !isMenuOpen),
                    child: Icon(isMenuOpen ? Icons.close : Icons.layers, color: cNeon, size: 20),
                  ),

                  if (isMenuOpen) ...[
                    const SizedBox(height: 10),
                    Container(
                        width: 180,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8), border: Border.all(color: cNeon.withValues(alpha: 0.5))),
                        child: Column(
                            children: [
                              Theme(
                                data: ThemeData(unselectedWidgetColor: Colors.white54),
                                child: CheckboxListTile(
                                  title: const Text("Satellite View", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  value: showMapArt,
                                  activeColor: cNeon, checkColor: Colors.black,
                                  dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  onChanged: (v) => setState(() => showMapArt = v ?? true),
                                ),
                              ),
                              Theme(
                                data: ThemeData(unselectedWidgetColor: Colors.white54),
                                child: CheckboxListTile(
                                  title: const Text("Zoning Map", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  value: showDistrictZoning,
                                  activeColor: Colors.cyanAccent, checkColor: Colors.black,
                                  dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  onChanged: (v) => setState(() => showDistrictZoning = v ?? false),
                                ),
                              ),

                              const Divider(color: Colors.white24, height: 30),
                              const Text("ZOOM", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),

                              SizedBox(
                                height: 140,
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                      value: currentZoom,
                                      min: -5.0,
                                      max: 4.0,
                                      activeColor: cNeon,
                                      inactiveColor: Colors.white24,
                                      onChanged: (v) {
                                        setState(() => currentZoom = v);
                                        _mapController.move(_mapController.camera.center, v);
                                      }
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: cDark, side: const BorderSide(color: Colors.white30)),
                                    icon: const Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
                                    label: const Text("RESET", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      _mapController.move(mapCenter!, -2.0);
                                      setState(() { currentZoom = -2.0; selectedBlockId = null; });
                                    }
                                ),
                              )
                            ]
                        )
                    )
                  ]
                ],
              )
          ),

          if (selectedBlockId != null) ...[
            GestureDetector(onTap: () => setState(() => selectedBlockId = null), child: Container(color: Colors.black.withValues(alpha: 0.4), width: double.infinity, height: double.infinity)),
            Center(child: Material(color: Colors.transparent, child: _buildTacticalModal())),
          ]
        ],
      ),
    );
  }
}