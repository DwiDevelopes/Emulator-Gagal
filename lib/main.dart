import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

// Tambahkan ini untuk Android
import 'package:webview_flutter_android/webview_flutter_android.dart';
// Tambahkan ini untuk iOS
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EmuFlash',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6AE0),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          elevation: 2,
          centerTitle: true,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        cardColor: const Color(0xFF1E1E2E),
        dialogBackgroundColor: const Color(0xFF1E1E2E),
      ),
      home: const HomeScreen(),
    );
  }
}

// Model untuk data game
class GameData {
  String id;
  String fileName;
  String displayName;
  String filePath;
  String? coverPath;
  DateTime lastPlayed;
  int playCount;
  FileSize fileSize;
  String fileType; // 'swf', 'html', 'link'
  String? gameUrl; // untuk tipe link

  GameData({
    required this.id,
    required this.fileName,
    required this.displayName,
    required this.filePath,
    this.coverPath,
    required this.lastPlayed,
    required this.playCount,
    required this.fileSize,
    required this.fileType,
    this.gameUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'displayName': displayName,
        'filePath': filePath,
        'coverPath': coverPath,
        'lastPlayed': lastPlayed.toIso8601String(),
        'playCount': playCount,
        'fileSize': fileSize.toJson(),
        'fileType': fileType,
        'gameUrl': gameUrl,
      };

  factory GameData.fromJson(Map<String, dynamic> json) => GameData(
        id: json['id'],
        fileName: json['fileName'],
        displayName: json['displayName'],
        filePath: json['filePath'],
        coverPath: json['coverPath'],
        lastPlayed: DateTime.parse(json['lastPlayed']),
        playCount: json['playCount'] ?? 0,
        fileSize: FileSize.fromJson(json['fileSize']),
        fileType: json['fileType'] ?? 'swf',
        gameUrl: json['gameUrl'],
      );
}

class FileSize {
  final int bytes;

  FileSize(this.bytes);

  String get formatted {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Map<String, dynamic> toJson() => {'bytes': bytes};

  factory FileSize.fromJson(Map<String, dynamic> json) =>
      FileSize(json['bytes']);
}

// Service untuk mengelola data game
class GameDataService {
  static const String _gameDataFile = 'games_data.json';
  static const String _coversDir = 'covers';
  static const String _gamesDir = 'games';
  static const String _htmlDir = 'html_games';

  Future<List<GameData>> loadGameData() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dataFile = File('${appDir.path}/$_gameDataFile');
      
      if (await dataFile.exists()) {
        final content = await dataFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((json) => GameData.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error loading game data: $e');
    }
    return [];
  }

  Future<void> saveGameData(List<GameData> games) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dataFile = File('${appDir.path}/$_gameDataFile');
      
      final jsonList = games.map((game) => game.toJson()).toList();
      await dataFile.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('Error saving game data: $e');
    }
  }

  Future<String?> saveCoverImage(File imageFile, String gameId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory('${appDir.path}/$_coversDir');
      
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final imageBytes = await imageFile.readAsBytes();
      
      if (imageBytes.isEmpty) {
        throw Exception('Image file is empty');
      }

      final originalImage = img.decodeImage(imageBytes);
      
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }

      final resizedImage = img.copyResize(
        originalImage, 
        width: 400, 
        height: 600,
        maintainAspect: false,
      );
      
      final resizedBytes = img.encodeJpg(resizedImage, quality: 90);
      
      if (resizedBytes.isEmpty) {
        throw Exception('Failed to encode resized image');
      }

      final coverPath = '${coversDir.path}/$gameId.jpg';
      final coverFile = File(coverPath);
      await coverFile.writeAsBytes(resizedBytes);
      
      return coverPath;
    } catch (e) {
      print('Error saving cover image: $e');
      return null;
    }
  }

  Future<void> deleteCoverImage(String? coverPath) async {
    try {
      if (coverPath != null && await File(coverPath).exists()) {
        await File(coverPath).delete();
      }
    } catch (e) {
      print('Error deleting cover image: $e');
    }
  }

  Future<String> getDefaultCover() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final defaultCoverPath = '${appDir.path}/default_cover.jpg';
      
      if (!await File(defaultCoverPath).exists()) {
        final image = img.Image(width: 400, height: 600);
        
        // Gradient background
        for (var y = 0; y < 600; y++) {
          for (var x = 0; x < 400; x++) {
            final r = (x / 400 * 50).toInt() + 20;
            final g = (y / 600 * 50).toInt() + 20;
            final b = 100;
            image.setPixel(x, y, img.ColorRgb8(r, g, b));
          }
        }
        
        // Add game icon in center
        final iconX = 150;
        final iconY = 200;
        for (var y = 0; y < 200; y++) {
          for (var x = 0; x < 100; x++) {
            if ((x - 50) * (x - 50) + (y - 100) * (y - 100) < 2500) {
              image.setPixel(iconX + x, iconY + y, img.ColorRgb8(45, 106, 224));
            }
          }
        }
        
        await File(defaultCoverPath).writeAsBytes(img.encodeJpg(image));
      }
      
      return defaultCoverPath;
    } catch (e) {
      print('Error creating default cover: $e');
      return '';
    }
  }

  Future<String> saveGameFile(File sourceFile, String gameId, String fileType) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${appDir.path}/$_gamesDir');
      
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final extension = path.extension(sourceFile.path);
      final targetPath = '${targetDir.path}/$gameId$extension';
      
      await sourceFile.copy(targetPath);
      
      return targetPath;
    } catch (e) {
      print('Error saving game file: $e');
      return '';
    }
  }

  Future<String> saveHtmlContent(String htmlContent, String gameId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final htmlDir = Directory('${appDir.path}/$_htmlDir');
      
      if (!await htmlDir.exists()) {
        await htmlDir.create(recursive: true);
      }

      final targetPath = '${htmlDir.path}/$gameId.html';
      final htmlFile = File(targetPath);
      await htmlFile.writeAsString(htmlContent);
      
      return targetPath;
    } catch (e) {
      print('Error saving HTML content: $e');
      return '';
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GameDataService _gameService = GameDataService();
  List<GameData> _games = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedCategory = 'all';
  int _selectedIndex = 0;
  int _currentPage = 0;
  final int _gamesPerPage = 8;

  final List<String> _categories = [
    'all',
    'swf',
    'html',
    'link',
    'recent',
    'favorite'
  ];

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    setState(() => _isLoading = true);
    try {
      _games = await _gameService.loadGameData();
      _games.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    } catch (e) {
      print('Error loading games: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _pickGameFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['swf', 'html', 'htm'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.single.path!);
        final extension = path.extension(file.path).toLowerCase();
        
        if (extension == '.swf') {
          await _addSWFGame(file);
        } else if (extension == '.html' || extension == '.htm') {
          await _addHTMLGame(file);
        }
      }
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  Future<void> _addSWFGame(File swfFile) async {
    try {
      final fileName = path.basename(swfFile.path);
      final gameId = '${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode}';
      
      final gamePath = await _gameService.saveGameFile(swfFile, gameId, 'swf');
      
      final gameData = GameData(
        id: gameId,
        fileName: fileName,
        displayName: fileName.replaceAll('.swf', ''),
        filePath: gamePath,
        coverPath: await _gameService.getDefaultCover(),
        lastPlayed: DateTime.now(),
        playCount: 0,
        fileSize: FileSize(swfFile.lengthSync()),
        fileType: 'swf',
      );

      _games.add(gameData);
      await _gameService.saveGameData(_games);
      await _loadGames();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Game added: ${gameData.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Error adding game: $e');
    }
  }

  Future<void> _addHTMLGame(File htmlFile) async {
    try {
      final content = await htmlFile.readAsString();
      final fileName = path.basename(htmlFile.path);
      final gameId = '${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode}';
      
      final gamePath = await _gameService.saveHtmlContent(content, gameId);
      
      final gameData = GameData(
        id: gameId,
        fileName: fileName,
        displayName: fileName.replaceAll('.html', '').replaceAll('.htm', ''),
        filePath: gamePath,
        coverPath: await _gameService.getDefaultCover(),
        lastPlayed: DateTime.now(),
        playCount: 0,
        fileSize: FileSize(htmlFile.lengthSync()),
        fileType: 'html',
      );

      _games.add(gameData);
      await _gameService.saveGameData(_games);
      await _loadGames();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('HTML Game added: ${gameData.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Error adding HTML game: $e');
    }
  }

  Future<void> _addLinkGame() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const AddLinkDialog(),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final parts = result.split('||');
        final name = parts[0];
        final link = parts[1];
        
        final gameId = '${DateTime.now().millisecondsSinceEpoch}_${link.hashCode}';
        
        final gameData = GameData(
          id: gameId,
          fileName: name,
          displayName: name,
          filePath: link,
          coverPath: await _gameService.getDefaultCover(),
          lastPlayed: DateTime.now(),
          playCount: 0,
          fileSize: FileSize(0),
          fileType: 'link',
          gameUrl: link,
        );

        _games.add(gameData);
        await _gameService.saveGameData(_games);
        await _loadGames();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Link Game added: $name'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        _showError('Error adding link game: $e');
      }
    }
  }

  Future<void> _editGameCover(GameData game) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => EditCoverDialog(game: game, gameService: _gameService),
    );

    if (result != null && mounted) {
      game.coverPath = result;
      await _gameService.saveGameData(_games);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _deleteGame(GameData game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Game'),
        content: Text('Delete "${game.displayName}"?'),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        if (game.fileType != 'link') {
          final gameFile = File(game.filePath);
          if (await gameFile.exists()) {
            await gameFile.delete();
          }
        }

        if (game.coverPath != null && !game.coverPath!.contains('default_cover')) {
          await _gameService.deleteCoverImage(game.coverPath);
        }

        _games.removeWhere((g) => g.id == game.id);
        await _gameService.saveGameData(_games);
        
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Game deleted: ${game.displayName}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        _showError('Error deleting game: $e');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<GameData> get _filteredGames {
    List<GameData> filtered = _games;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((game) =>
          game.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          game.fileName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    // Filter by category
    if (_selectedCategory != 'all') {
      if (_selectedCategory == 'recent') {
        filtered.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
      } else if (_selectedCategory == 'favorite') {
        // You can add favorite logic here
      } else {
        filtered = filtered.where((game) => game.fileType == _selectedCategory).toList();
      }
    }

    return filtered;
  }

  List<GameData> get _paginatedGames {
    final start = _currentPage * _gamesPerPage;
    final end = start + _gamesPerPage;
    return _filteredGames.length > end 
        ? _filteredGames.sublist(start, end)
        : _filteredGames.sublist(start);
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query;
      _currentPage = 0;
    });
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
      _currentPage = 0;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    
    if (index == 1) {
      _showAddMenu();
    } else if (index == 2) {
      _openCanvasPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EmuFlash'),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGames,
            tooltip: 'Refresh Games',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2D6AE0), width: 1),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Icon(Icons.search, color: Colors.grey),
                  ),
                  Expanded(
                    child: TextField(
                      onChanged: _onSearch,
                      decoration: const InputDecoration(
                        hintText: 'Search games...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () => _onSearch(''),
                    ),
                ],
              ),
            ),
          ),

          // Category Tabs
          Container(
            height: 50,
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: ChoiceChip(
                    label: Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF2D6AE0),
                    backgroundColor: const Color(0xFF2A2A3E),
                    onSelected: (_) => _onCategorySelected(category),
                  ),
                );
              },
            ),
          ),

          // Games Grid
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF2D6AE0),
                    ),
                  )
                : _filteredGames.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.games,
                              size: 100,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No games found'
                                  : 'No games yet',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: _showAddMenu,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Your First Game'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D6AE0),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: 0.6,
                              ),
                              itemCount: _paginatedGames.length,
                              itemBuilder: (context, index) {
                                final game = _paginatedGames[index];
                                return _buildGameCard(game);
                              },
                            ),
                          ),
                          
                          // Pagination
                          if (_filteredGames.length > _gamesPerPage)
                            Container(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: _currentPage > 0
                                        ? () {
                                            setState(() {
                                              _currentPage--;
                                            });
                                          }
                                        : null,
                                  ),
                                  Text(
                                    'Page ${_currentPage + 1} of ${(_filteredGames.length / _gamesPerPage).ceil()}',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: (_currentPage + 1) * _gamesPerPage < _filteredGames.length
                                        ? () {
                                            setState(() {
                                              _currentPage++;
                                            });
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A2E),
        selectedItemColor: const Color(0xFF2D6AE0),
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Add Game',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.create),
            label: 'Canvas',
          ),
        ],
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Add Game',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file, color: Color(0xFF2D6AE0)),
                title: const Text('Add SWF File', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Import SWF game file', style: TextStyle(color: Colors.grey)),
                onTap: () {
                  Navigator.pop(context);
                  _pickGameFile();
                },
              ),
              const Divider(color: Colors.grey, height: 1),
              ListTile(
                leading: const Icon(Icons.code, color: Color(0xFF2D6AE0)),
                title: const Text('Add HTML Game', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Import HTML game file', style: TextStyle(color: Colors.grey)),
                onTap: () {
                  Navigator.pop(context);
                  _pickGameFile();
                },
              ),
              const Divider(color: Colors.grey, height: 1),
              ListTile(
                leading: const Icon(Icons.link, color: Color(0xFF2D6AE0)),
                title: const Text('Add Game Link', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Add online game URL', style: TextStyle(color: Colors.grey)),
                onTap: () {
                  Navigator.pop(context);
                  _addLinkGame();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _openCanvasPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CanvasPage(gameService: _gameService),
      ),
    );
  }

  Widget _buildGameCard(GameData game) {
    return GestureDetector(
      onTap: () {
        game.playCount++;
        game.lastPlayed = DateTime.now();
        _gameService.saveGameData(_games);
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GameScreen(
              gameData: game,
              onUpdate: () => _gameService.saveGameData(_games),
            ),
          ),
        );
      },
      onLongPress: () => _editGameCover(game),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A3E), width: 1),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover Image
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      image: game.coverPath != null
                          ? DecorationImage(
                              image: FileImage(File(game.coverPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: const Color(0xFF2A2A3E),
                    ),
                    child: game.coverPath == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  game.fileType == 'swf' 
                                    ? Icons.games 
                                    : game.fileType == 'html' 
                                      ? Icons.code 
                                      : Icons.link,
                                  size: 40,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  game.displayName,
                                  style: const TextStyle(color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                ),
                
                // Game Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: game.fileType == 'swf' 
                                ? const Color(0xFF2D6AE0) 
                                : game.fileType == 'html'
                                  ? Colors.green
                                  : Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              game.fileType.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            game.fileSize.formatted,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.play_arrow,
                            size: 10,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${game.playCount}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDate(game.lastPlayed),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Delete Button
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _deleteGame(game),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // File Type Badge
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  game.fileType == 'swf' ? 'SWF' : game.fileType == 'html' ? 'HTML' : 'LINK',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      return '${difference.inDays ~/ 7}w ago';
    } else {
      return '${difference.inDays ~/ 30}m ago';
    }
  }
}

class AddLinkDialog extends StatefulWidget {
  const AddLinkDialog({super.key});

  @override
  State<AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<AddLinkDialog> {
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _linkController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text(
        'Add Game Link',
        style: TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _linkController,
              decoration: const InputDecoration(
                labelText: 'Game URL',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link, color: Colors.grey),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF2D6AE0)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Game Name (optional)',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit, color: Colors.grey),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF2D6AE0)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            final link = _linkController.text.trim();
            final name = _nameController.text.trim();
            
            if (link.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter a valid URL'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            
            // Validate URL
            try {
              Uri.parse(link);
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Invalid URL: $e'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            
            final displayName = name.isNotEmpty ? name : Uri.parse(link).host;
            Navigator.of(context).pop('$displayName||$link');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D6AE0),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class EditCoverDialog extends StatefulWidget {
  final GameData game;
  final GameDataService gameService;

  const EditCoverDialog({
    super.key,
    required this.game,
    required this.gameService,
  });

  @override
  State<EditCoverDialog> createState() => _EditCoverDialogState();
}

class _EditCoverDialogState extends State<EditCoverDialog> {
  File? _selectedImageFile;
  bool _isSaving = false;

  Future<void> _pickCoverImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );

      if (image != null) {
        setState(() {
          _selectedImageFile = File(image.path);
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _saveCoverImage() async {
    if (_selectedImageFile == null) return null;
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      final coverPath = await widget.gameService.saveCoverImage(
        _selectedImageFile!,
        widget.game.id,
      );
      
      setState(() {
        _isSaving = false;
      });
      
      return coverPath;
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      print('Error saving cover: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text(
        'Edit Game Cover',
        style: TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Game Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: widget.game.coverPath != null
                          ? DecorationImage(
                              image: FileImage(File(widget.game.coverPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: const Color(0xFF1E1E2E),
                    ),
                    child: widget.game.coverPath == null
                        ? const Icon(Icons.games, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.game.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Type: ${widget.game.fileType.toUpperCase()}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          'Size: ${widget.game.fileSize.formatted}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          'Plays: ${widget.game.playCount}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Cover Image Preview
            GestureDetector(
              onTap: _pickCoverImage,
              child: Container(
                width: 200,
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF2A2A3E),
                  border: Border.all(
                    color: const Color(0xFF2D6AE0),
                    width: 2,
                  ),
                  image: (_selectedImageFile != null)
                      ? DecorationImage(
                          image: FileImage(_selectedImageFile!),
                          fit: BoxFit.cover,
                        )
                      : (widget.game.coverPath != null)
                          ? DecorationImage(
                              image: FileImage(File(widget.game.coverPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                ),
                child: _selectedImageFile == null && 
                       widget.game.coverPath == null
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate, 
                                 size: 50, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              'Tap to add\ncover image', 
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : null,
              ),
            ),
            
            if (_isSaving) ...[
              const SizedBox(height: 10),
              const CircularProgressIndicator(color: Color(0xFF2D6AE0)),
              const SizedBox(height: 10),
              const Text(
                'Saving cover...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : () async {
            if (_selectedImageFile != null) {
              final newCoverPath = await _saveCoverImage();
              if (newCoverPath != null && mounted) {
                Navigator.of(context).pop(newCoverPath);
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to save cover image'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } else {
              Navigator.of(context).pop();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D6AE0),
          ),
          child: _isSaving 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class WebViewPage extends StatefulWidget {
  final String htmlContent;
  final String title;

  const WebViewPage({
    super.key,
    required this.htmlContent,
    required this.title,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(widget.htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

// Then continue with CanvasPage class
class CanvasPage extends StatefulWidget {
  final GameDataService gameService;

  const CanvasPage({super.key, required this.gameService});

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  final TextEditingController _htmlController = TextEditingController();
  final TextEditingController _cssController = TextEditingController();
  final TextEditingController _jsController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

@override
void initState() {
  super.initState();
  
  _htmlController.text = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Tetris Game</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            overflow: hidden;
            font-family: 'Arial', sans-serif;
        }
        #gameContainer {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 20px;
            padding: 20px;
        }
        #gameCanvas {
            border: 4px solid #2d6ae0;
            border-radius: 10px;
            box-shadow: 0 0 30px rgba(45, 106, 224, 0.3);
            background: #0f0f1a;
            max-width: 100%;
            height: auto;
        }
        #infoPanel {
            color: white;
            text-align: center;
            background: rgba(0, 0, 0, 0.5);
            padding: 15px;
            border-radius: 10px;
            border: 2px solid #2d6ae0;
            min-width: 250px;
        }
        #score {
            font-size: 28px;
            color: #00ff88;
            margin: 10px 0;
            text-shadow: 0 0 10px rgba(0, 255, 136, 0.5);
        }
        #level {
            font-size: 20px;
            color: #ffcc00;
        }
        .controls {
            margin-top: 15px;
            font-size: 14px;
            color: #aaa;
        }
        .button {
            background: #2d6ae0;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            margin: 5px;
            cursor: pointer;
            font-size: 16px;
            transition: all 0.3s;
        }
        .button:hover {
            background: #4a8cff;
            transform: scale(1.05);
        }
        @media (max-width: 768px) {
            #gameContainer {
                flex-direction: column;
            }
            #gameCanvas {
                width: 90vw;
                height: 90vw;
                max-width: 500px;
                max-height: 500px;
            }
            .controls {
                font-size: 12px;
            }
        }
    </style>
</head>
<body>
    <div id="gameContainer">
        <canvas id="gameCanvas"></canvas>
        <div id="infoPanel">
            <h2 style="margin: 0; color: #2d6ae0;">TETRIS</h2>
            <div id="score">Score: 0</div>
            <div id="level">Level: 1</div>
            <div id="lines">Lines: 0</div>
            <div class="controls">
                <div>← → : Move</div>
                <div>↑ : Rotate</div>
                <div>↓ : Soft Drop</div>
                <div>Space : Hard Drop</div>
                <div>P : Pause</div>
            </div>
            <button class="button" onclick="resetGame()">Restart Game</button>
        </div>
    </div>
    <script>
        // Game Tetris JavaScript code
    </script>
</body>
</html>
''';

  _cssController.text = '''
body {
    margin: 0;
    padding: 0;
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
    overflow: hidden;
    font-family: 'Arial', sans-serif;
}
#gameContainer {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 20px;
    padding: 20px;
}
#gameCanvas {
    border: 4px solid #2d6ae0;
    border-radius: 10px;
    box-shadow: 0 0 30px rgba(45, 106, 224, 0.3);
    background: #0f0f1a;
    max-width: 100%;
    height: auto;
}
#infoPanel {
    color: white;
    text-align: center;
    background: rgba(0, 0, 0, 0.5);
    padding: 15px;
    border-radius: 10px;
    border: 2px solid #2d6ae0;
    min-width: 250px;
}
#score {
    font-size: 28px;
    color: #00ff88;
    margin: 10px 0;
    text-shadow: 0 0 10px rgba(0, 255, 136, 0.5);
}
#level {
    font-size: 20px;
    color: #ffcc00;
}
.controls {
    margin-top: 15px;
    font-size: 14px;
    color: #aaa;
}
.button {
    background: #2d6ae0;
    color: white;
    border: none;
    padding: 10px 20px;
    border-radius: 5px;
    margin: 5px;
    cursor: pointer;
    font-size: 16px;
    transition: all 0.3s;
}
.button:hover {
    background: #4a8cff;
    transform: scale(1.05);
}
@media (max-width: 768px) {
    #gameContainer {
        flex-direction: column;
    }
    #gameCanvas {
        width: 90vw;
        height: 90vw;
        max-width: 500px;
        max-height: 500px;
    }
    .controls {
        font-size: 12px;
    }
}
''';

  _jsController.text = '''
const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');
const scoreElement = document.getElementById('score');
const levelElement = document.getElementById('level');
const linesElement = document.getElementById('lines');

// Responsive canvas setup
function setupCanvas() {
    const container = document.getElementById('gameContainer');
    const size = Math.min(400, window.innerWidth * 0.8, window.innerHeight * 0.6);
    
    canvas.width = size;
    canvas.height = size * 1.5; // Tetris aspect ratio
    
    BLOCK_SIZE = canvas.width / COLS;
}

// Game constants
let COLS = 10;
let ROWS = 20;
let BLOCK_SIZE;
const COLORS = [
    null,
    '#FF0D72', // I
    '#0DC2FF', // J
    '#0DFF72', // L
    '#F538FF', // O
    '#FF8E0D', // S
    '#FFE138', // T
    '#3877FF'  // Z
];

// Tetrominoes
const SHAPES = [
    null,
    [[0,0,0,0], [1,1,1,1], [0,0,0,0], [0,0,0,0]], // I
    [[2,0,0], [2,2,2], [0,0,0]], // J
    [[0,0,3], [3,3,3], [0,0,0]], // L
    [[4,4], [4,4]], // O
    [[0,5,5], [5,5,0], [0,0,0]], // S
    [[0,6,0], [6,6,6], [0,0,0]], // T
    [[7,7,0], [0,7,7], [0,0,0]]  // Z
];

// Game variables
let board = [];
let score = 0;
let level = 1;
let lines = 0;
let dropCounter = 0;
let dropInterval = 1000; // ms
let lastTime = 0;
let gameOver = false;
let paused = false;
let currentPiece = null;
let nextPiece = null;

// Initialize game
function init() {
    setupCanvas();
    createBoard();
    resetPiece();
    
    // Handle window resize
    window.addEventListener('resize', setupCanvas);
    
    // Game controls
    document.addEventListener('keydown', handleKeyPress);
    
    // Start game loop
    requestAnimationFrame(update);
}

// Create empty board
function createBoard() {
    board = Array.from({length: ROWS}, () => Array(COLS).fill(0));
}

// Create random piece
function createPiece() {
    const pieceId = Math.floor(Math.random() * 7) + 1;
    return {
        id: pieceId,
        shape: SHAPES[pieceId],
        x: Math.floor(COLS / 2) - Math.floor(SHAPES[pieceId][0].length / 2),
        y: 0,
        color: COLORS[pieceId]
    };
}

// Reset current piece
function resetPiece() {
    currentPiece = nextPiece || createPiece();
    nextPiece = createPiece();
    
    // Check game over
    if (collision()) {
        gameOver = true;
    }
}

// Check collision
function collision() {
    for (let y = 0; y < currentPiece.shape.length; y++) {
        for (let x = 0; x < currentPiece.shape[y].length; x++) {
            if (currentPiece.shape[y][x]) {
                const newX = currentPiece.x + x;
                const newY = currentPiece.y + y;
                
                if (newX < 0 || newX >= COLS || 
                    newY >= ROWS || 
                    (newY >= 0 && board[newY][newX])) {
                    return true;
                }
            }
        }
    }
    return false;
}

// Merge piece to board
function merge() {
    for (let y = 0; y < currentPiece.shape.length; y++) {
        for (let x = 0; x < currentPiece.shape[y].length; x++) {
            if (currentPiece.shape[y][x]) {
                const boardY = currentPiece.y + y;
                if (boardY >= 0) {
                    board[boardY][currentPiece.x + x] = currentPiece.id;
                }
            }
        }
    }
}

// Clear completed lines
function clearLines() {
    let linesCleared = 0;
    
    outer: for (let y = ROWS - 1; y >= 0; y--) {
        for (let x = 0; x < COLS; x++) {
            if (board[y][x] === 0) {
                continue outer;
            }
        }
        
        // Remove line and add new empty line at top
        const row = board.splice(y, 1)[0].fill(0);
        board.unshift(row);
        linesCleared++;
        y++; // Check same row again
    }
    
    if (linesCleared > 0) {
        // Update score
        const linePoints = [0, 40, 100, 300, 1200];
        score += linePoints[linesCleared] * level;
        lines += linesCleared;
        level = Math.floor(lines / 10) + 1;
        dropInterval = Math.max(100, 1000 - (level - 1) * 100);
        
        updateUI();
    }
}

// Move piece
function movePiece(dx, dy) {
    if (gameOver || paused) return;
    
    currentPiece.x += dx;
    currentPiece.y += dy;
    
    if (collision()) {
        currentPiece.x -= dx;
        currentPiece.y -= dy;
        
        if (dy > 0) {
            merge();
            clearLines();
            resetPiece();
        }
        return false;
    }
    return true;
}

// Rotate piece
function rotatePiece() {
    if (gameOver || paused) return;
    
    const originalShape = currentPiece.shape;
    const rows = originalShape.length;
    const cols = originalShape[0].length;
    const rotated = Array.from({length: cols}, () => Array(rows).fill(0));
    
    // Rotate matrix
    for (let y = 0; y < rows; y++) {
        for (let x = 0; x < cols; x++) {
            rotated[x][rows - 1 - y] = originalShape[y][x];
        }
    }
    
    currentPiece.shape = rotated;
    
    if (collision()) {
        currentPiece.shape = originalShape;
    }
}

// Hard drop
function hardDrop() {
    if (gameOver || paused) return;
    
    while (movePiece(0, 1)) {}
}

// Draw functions
function drawBoard() {
    // Draw background grid
    ctx.fillStyle = '#0f0f1a';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    // Draw grid lines
    ctx.strokeStyle = 'rgba(45, 106, 224, 0.3)';
    ctx.lineWidth = 1;
    
    for (let x = 0; x <= COLS; x++) {
        ctx.beginPath();
        ctx.moveTo(x * BLOCK_SIZE, 0);
        ctx.lineTo(x * BLOCK_SIZE, canvas.height);
        ctx.stroke();
    }
    
    for (let y = 0; y <= ROWS; y++) {
        ctx.beginPath();
        ctx.moveTo(0, y * BLOCK_SIZE);
        ctx.lineTo(canvas.width, y * BLOCK_SIZE);
        ctx.stroke();
    }
    
    // Draw placed blocks
    for (let y = 0; y < ROWS; y++) {
        for (let x = 0; x < COLS; x++) {
            if (board[y][x]) {
                drawBlock(x, y, board[y][x]);
            }
        }
    }
}

function drawBlock(x, y, type) {
    const color = COLORS[type];
    
    // Block with gradient effect
    const gradient = ctx.createLinearGradient(
        x * BLOCK_SIZE, y * BLOCK_SIZE,
        x * BLOCK_SIZE + BLOCK_SIZE, y * BLOCK_SIZE + BLOCK_SIZE
    );
    gradient.addColorStop(0, color);
    gradient.addColorStop(1, darkenColor(color, 0.3));
    
    ctx.fillStyle = gradient;
    ctx.fillRect(x * BLOCK_SIZE, y * BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE);
    
    // Block border
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1;
    ctx.strokeRect(x * BLOCK_SIZE, y * BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE);
    
    // Inner highlight
    ctx.fillStyle = 'rgba(255, 255, 255, 0.2)';
    ctx.fillRect(x * BLOCK_SIZE + 2, y * BLOCK_SIZE + 2, BLOCK_SIZE - 4, 4);
    ctx.fillRect(x * BLOCK_SIZE + 2, y * BLOCK_SIZE + 2, 4, BLOCK_SIZE - 4);
}

function drawCurrentPiece() {
    if (!currentPiece) return;
    
    for (let y = 0; y < currentPiece.shape.length; y++) {
        for (let x = 0; x < currentPiece.shape[y].length; x++) {
            if (currentPiece.shape[y][x]) {
                drawBlock(currentPiece.x + x, currentPiece.y + y, currentPiece.id);
            }
        }
    }
}

function drawNextPiecePreview() {
    if (!nextPiece) return;
    
    const previewSize = BLOCK_SIZE * 2;
    const previewX = canvas.width + 20;
    const previewY = 50;
    
    // Draw preview box
    ctx.fillStyle = 'rgba(0, 0, 0, 0.5)';
    ctx.fillRect(previewX, previewY, previewSize * 4, previewSize * 4);
    ctx.strokeStyle = '#2d6ae0';
    ctx.lineWidth = 2;
    ctx.strokeRect(previewX, previewY, previewSize * 4, previewSize * 4);
    
    ctx.fillStyle = 'white';
    ctx.font = '16px Arial';
    ctx.fillText('Next:', previewX + 10, previewY - 10);
    
    // Draw next piece
    for (let y = 0; y < nextPiece.shape.length; y++) {
        for (let x = 0; x < nextPiece.shape[y].length; x++) {
            if (nextPiece.shape[y][x]) {
                ctx.fillStyle = COLORS[nextPiece.id];
                ctx.fillRect(
                    previewX + x * previewSize + 10,
                    previewY + y * previewSize + 10,
                    previewSize - 2,
                    previewSize - 2
                );
            }
        }
    }
}

function drawGameInfo() {
    if (gameOver) {
        ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        ctx.fillStyle = '#ff4757';
        ctx.font = 'bold 40px Arial';
        ctx.textAlign = 'center';
        ctx.fillText('GAME OVER', canvas.width / 2, canvas.height / 2 - 30);
        
        ctx.fillStyle = 'white';
        ctx.font = '20px Arial';
        ctx.fillText('Press Restart to play again', canvas.width / 2, canvas.height / 2 + 30);
        ctx.textAlign = 'left';
    }
    
    if (paused) {
        ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        ctx.fillStyle = '#ffcc00';
        ctx.font = 'bold 40px Arial';
        ctx.textAlign = 'center';
        ctx.fillText('PAUSED', canvas.width / 2, canvas.height / 2);
        ctx.textAlign = 'left';
    }
}

// Helper function to darken color
function darkenColor(color, amount) {
    const hex = color.replace('#', '');
    let r = parseInt(hex.substr(0, 2), 16);
    let g = parseInt(hex.substr(2, 2), 16);
    let b = parseInt(hex.substr(4, 2), 16);
    
    r = Math.floor(r * (1 - amount));
    g = Math.floor(g * (1 - amount));
    b = Math.floor(b * (1 - amount));
    
    return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
}

// Update UI
function updateUI() {
    scoreElement.textContent = 'Score: ' + score;
    levelElement.textContent = 'Level: ' + level;
    linesElement.textContent = 'Lines: ' + lines;
}

// Handle keyboard input
function handleKeyPress(event) {
    switch(event.key) {
        case 'ArrowLeft':
            movePiece(-1, 0);
            break;
        case 'ArrowRight':
            movePiece(1, 0);
            break;
        case 'ArrowDown':
            movePiece(0, 1);
            break;
        case 'ArrowUp':
            rotatePiece();
            break;
        case ' ':
            hardDrop();
            break;
        case 'p':
        case 'P':
            paused = !paused;
            break;
    }
}

// Game loop
function update(time = 0) {
    const deltaTime = time - lastTime;
    lastTime = time;
    
    if (!paused && !gameOver) {
        dropCounter += deltaTime;
        if (dropCounter > dropInterval) {
            movePiece(0, 1);
            dropCounter = 0;
        }
    }
    
    // Draw everything
    drawBoard();
    drawCurrentPiece();
    drawNextPiecePreview();
    drawGameInfo();
    
    requestAnimationFrame(update);
}

// Reset game
function resetGame() {
    board = Array.from({length: ROWS}, () => Array(COLS).fill(0));
    score = 0;
    level = 1;
    lines = 0;
    dropInterval = 1000;
    gameOver = false;
    paused = false;
    currentPiece = null;
    nextPiece = null;
    resetPiece();
    updateUI();
}

// Initialize game on load
window.addEventListener('load', init);

// Make reset function global for button
window.resetGame = resetGame;
''';
    _nameController.text = 'Canvas Game ${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _htmlController.dispose();
    _cssController.dispose();
    _jsController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveGame() async {
    try {
      _updateHtmlFromParts();
      final htmlContent = _htmlController.text;
      final gameId = '${DateTime.now().millisecondsSinceEpoch}_canvas';
      
      final gamePath = await widget.gameService.saveHtmlContent(htmlContent, gameId);
      
      final gameData = GameData(
        id: gameId,
        fileName: '${_nameController.text}.html',
        displayName: _nameController.text,
        filePath: gamePath,
        coverPath: await widget.gameService.getDefaultCover(),
        lastPlayed: DateTime.now(),
        playCount: 0,
        fileSize: FileSize(htmlContent.length),
        fileType: 'html',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Canvas game saved: ${gameData.displayName}'),
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving canvas game: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _updateHtmlFromParts() {
    final html = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${_nameController.text}</title>
    <style>
${_cssController.text}
    </style>
</head>
<body>
    <canvas id="gameCanvas" width="800" height="600"></canvas>
    <script>
${_jsController.text}
    </script>
</body>
</html>
''';
    _htmlController.text = html;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTML Canvas Editor'),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveGame,
            tooltip: 'Save Game',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Game Name
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Game Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            
            const SizedBox(height: 20),
            
            // Tabbed Editor
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TabBar(
                        labelColor: const Color(0xFF2D6AE0),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: const Color(0xFF2D6AE0),
                        tabs: const [
                          Tab(text: 'HTML'),
                          Tab(text: 'CSS'),
                          Tab(text: 'JavaScript'),
                        ],
                      ),
                    ),
                    
                    Expanded(
                      child: TabBarView(
                        children: [
                          // HTML Tab
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFF2D6AE0)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: _htmlController,
                              maxLines: null,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          
                          // CSS Tab
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.green),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: _cssController,
                              maxLines: null,
                              onChanged: (_) => _updateHtmlFromParts(),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          
                          // JavaScript Tab
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.orange),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: _jsController,
                              maxLines: null,
                              onChanged: (_) => _updateHtmlFromParts(),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Preview Button
            ElevatedButton.icon(
              onPressed: () {
                _updateHtmlFromParts();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WebViewPage(
                      htmlContent: _htmlController.text,
                      title: _nameController.text,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.visibility),
              label: const Text('Preview Game'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6AE0),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  final GameData gameData;
  final VoidCallback onUpdate;

  const GameScreen({
    super.key,
    required this.gameData,
    required this.onUpdate,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late WebViewController _controller;
  bool _isLoading = true;
  bool _isFullscreen = false;
  int _fps = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeWebViewController();
    _startFpsCounter();
  }

  void _startFpsCounter() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        final now = DateTime.now();
        final diff = now.difference(_lastFpsUpdate);
        if (diff.inMilliseconds >= 1000) {
          setState(() {
            _fps = _frameCount;
            _frameCount = 0;
            _lastFpsUpdate = now;
          });
        }
      }
    });
  }

  Future<void> _initializeWebViewController() async {
    try {
      // Create WebViewController
      final PlatformWebViewControllerCreationParams params;
      
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      _controller = WebViewController.fromPlatformCreationParams(params);
      
      // Platform specific setup
      if (_controller.platform is AndroidWebViewController) {
        AndroidWebViewController.enableDebugging(true);
        (_controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      
      // Configure controller
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(const Color(0xFF000000));
      
      // Set navigation delegate
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView Error: ${error.description}');
          },
        ),
      );

      // Load the game content
      await _loadGameContent();
    } catch (e) {
      print('Error initializing WebView: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadGameContent() async {
    try {
      if (widget.gameData.fileType == 'link') {
        // Load external URL
        final url = widget.gameData.gameUrl!;
        if (!url.startsWith('http')) {
          await _controller.loadHtmlString('''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${widget.gameData.displayName}</title>
    <style>
        body { margin: 0; padding: 20px; background: #0f0f1a; color: white; font-family: Arial; }
        .error { color: #ff4757; }
    </style>
</head>
<body>
    <h1>Invalid URL</h1>
    <p class="error">The provided URL is not valid:</p>
    <p>$url</p>
    <p>Please make sure the URL starts with http:// or https://</p>
</body>
</html>
''');
        } else {
          await _controller.loadRequest(Uri.parse(url));
        }
      } else if (widget.gameData.fileType == 'html') {
        // Load HTML file
        final htmlFile = File(widget.gameData.filePath);
        if (await htmlFile.exists()) {
          final htmlContent = await htmlFile.readAsString();
          await _controller.loadHtmlString(htmlContent);
        } else {
          await _controller.loadHtmlString('''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${widget.gameData.displayName}</title>
    <style>
        body { margin: 0; padding: 20px; background: #0f0f1a; color: white; font-family: Arial; }
        .error { color: #ff4757; }
    </style>
</head>
<body>
    <h1>File Not Found</h1>
    <p class="error">The HTML file could not be found at:</p>
    <p>${widget.gameData.filePath}</p>
</body>
</html>
''');
        }
      } else if (widget.gameData.fileType == 'swf') {
        // Load SWF with Ruffle
        await _loadRuffleContent();
      }
    } catch (e) {
      print('Error loading game content: $e');
      await _controller.loadHtmlString('''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Error</title>
    <style>
        body { margin: 0; padding: 20px; background: #0f0f1a; color: white; font-family: Arial; }
        .error { color: #ff4757; }
    </style>
</head>
<body>
    <h1>Error Loading Game</h1>
    <p class="error">${e.toString()}</p>
</body>
</html>
''');
    }
  }

  Future<void> _loadRuffleContent() async {
    try {
      final swfFile = File(widget.gameData.filePath);
      if (!await swfFile.exists()) {
        await _controller.loadHtmlString('''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${widget.gameData.displayName}</title>
    <style>
        body { margin: 0; padding: 20px; background: #0f0f1a; color: white; font-family: Arial; }
        .error { color: #ff4757; }
    </style>
</head>
<body>
    <h1>SWF File Not Found</h1>
    <p class="error">The SWF file could not be found at:</p>
    <p>${widget.gameData.filePath}</p>
</body>
</html>
''');
        return;
      }

final swfBytes = await swfFile.readAsBytes();
final swfBase64 = base64Encode(swfBytes);

// Load Ruffle dari CDN
final ruffleHtml = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${widget.gameData.displayName}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            background: #000; 
            width: 100vw; 
            height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            overflow: hidden;
            font-family: Arial, sans-serif;
            touch-action: pan-x pan-y;
        }
        #ruffle-container {
            width: 100%;
            height: 100%;
            position: relative;
        }
        
        #ruffle-container canvas,
        #ruffle-container ruffle-player {
            width: 100% !important;
            height: 100% !important;
            object-fit: contain !important;
        }
        
        #loading {
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            color: white;
            font-size: 20px;
            text-align: center;
            background: rgba(0,0,0,0.8);
            padding: 20px;
            border-radius: 10px;
            z-index: 1000;
        }
        
        /* FPS Display */
        #fps-display {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: rgba(0,0,0,0.7);
            color: white;
            padding: 8px 15px;
            border-radius: 5px;
            font-size: 14px;
            z-index: 1001;
            backdrop-filter: blur(5px);
            border: 1px solid rgba(255,255,255,0.1);
        }
        
        /* Virtual Cursor */
        #virtual-cursor {
            position: fixed;
            width: 20px;
            height: 20px;
            border: 2px solid #4CAF50;
            border-radius: 50%;
            pointer-events: none;
            z-index: 999;
            transform: translate(-50%, -50%);
            transition: transform 0.1s;
            background: rgba(76, 175, 80, 0.3);
        }
        
        #virtual-cursor.clicking {
            border-color: #ff5722;
            background: rgba(255, 87, 34, 0.3);
            transform: translate(-50%, -50%) scale(0.8);
        }
        
        /* Control Panel Container */
        #control-panel {
            position: fixed;
            bottom: 60px;
            right: 20px;
            z-index: 1002;
            display: flex;
            flex-direction: column;
            gap: 10px;
            align-items: flex-end;
        }
        
        /* Control Buttons */
        .control-btn {
            background: rgba(0,0,0,0.8);
            color: white;
            border: none;
            padding: 10px 15px;
            border-radius: 50px;
            cursor: pointer;
            font-size: 16px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.1);
            transition: all 0.3s;
            display: flex;
            align-items: center;
            gap: 8px;
            min-width: 50px;
            justify-content: center;
        }
        
        .control-btn:hover {
            background: rgba(0,0,0,0.9);
            transform: scale(1.05);
        }
        
        .control-btn.active {
            background: rgba(76, 175, 80, 0.3);
            border-color: #4CAF50;
        }
        
        /* Settings Panel */
        #settings-panel {
            position: fixed;
            bottom: 100px;
            right: 20px;
            background: rgba(0,0,0,0.95);
            color: white;
            padding: 20px;
            border-radius: 15px;
            z-index: 1003;
            width: 350px;
            max-height: 70vh;
            overflow-y: auto;
            backdrop-filter: blur(15px);
            border: 1px solid rgba(255,255,255,0.1);
            box-shadow: 0 10px 30px rgba(0,0,0,0.5);
            display: none;
        }
        
        .settings-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        
        .settings-header h3 {
            font-size: 18px;
            font-weight: 600;
        }
        
        .close-btn {
            background: transparent;
            color: white;
            font-size: 24px;
            cursor: pointer;
            border: none;
            padding: 0;
            width: 30px;
            height: 30px;
            line-height: 1;
        }
        
        .close-btn:hover {
            color: #ff5722;
        }
        
        /* Setting Items */
        .setting-group {
            margin-bottom: 20px;
        }
        
        .setting-group h4 {
            margin-bottom: 10px;
            color: #4CAF50;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .setting-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 0;
            border-bottom: 1px solid rgba(255,255,255,0.05);
        }
        
        .setting-item:last-child {
            border-bottom: none;
        }
        
        .setting-item label {
            font-size: 14px;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .setting-item select, 
        .setting-item input[type="color"] {
            background: rgba(255,255,255,0.1);
            border: 1px solid rgba(255,255,255,0.2);
            color: white;
            padding: 5px 10px;
            border-radius: 4px;
            outline: none;
        }
        
        .setting-item input[type="checkbox"] {
            width: 18px;
            height: 18px;
            cursor: pointer;
        }
        
        .setting-item .checkbox-container {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        /* Virtual Gamepad - Arrow Keys */
        #arrow-gamepad {
            position: fixed;
            bottom: 150px;
            right: 30px;
            display: grid;
            grid-template-columns: repeat(3, 50px);
            grid-template-rows: repeat(3, 50px);
            gap: 6px;
            z-index: 1001;
            background: rgba(0,0,0,0.85);
            padding: 12px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.15);
            box-shadow: 0 8px 20px rgba(0,0,0,0.4);
            cursor: move;
            touch-action: none;
        }
        
        #arrow-gamepad.dragging {
            opacity: 0.9;
            border-color: #4CAF50;
        }
        
        .arrow-btn {
            background: linear-gradient(145deg, rgba(255,255,255,0.2), rgba(255,255,255,0.1));
            border: 1px solid rgba(255, 255, 255, 0.25);
            color: white;
            font-size: 20px;
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            user-select: none;
            transition: all 0.1s;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        
        .arrow-btn:hover {
            background: linear-gradient(145deg, rgba(255,255,255,0.3), rgba(255,255,255,0.2));
            transform: translateY(-2px);
        }
        
        .arrow-btn:active {
            background: linear-gradient(145deg, rgba(76, 175, 80, 0.6), rgba(76, 175, 80, 0.4));
            transform: translateY(0);
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }
        
        .arrow-btn.pressed {
            background: linear-gradient(145deg, rgba(76, 175, 80, 0.8), rgba(76, 175, 80, 0.6));
            transform: scale(0.95);
        }
        
        .arrow-btn.up {
            grid-column: 2;
            grid-row: 1;
        }
        
        .arrow-btn.left {
            grid-column: 1;
            grid-row: 2;
        }
        
        .arrow-btn.center {
            grid-column: 2;
            grid-row: 2;
            font-size: 14px;
            background: linear-gradient(145deg, rgba(255, 87, 34, 0.4), rgba(255, 87, 34, 0.2));
            border-color: rgba(255, 87, 34, 0.5);
        }
        
        .arrow-btn.right {
            grid-column: 3;
            grid-row: 2;
        }
        
        .arrow-btn.down {
            grid-column: 2;
            grid-row: 3;
        }
        
        /* WASD Gamepad */
        #wasd-gamepad {
            position: fixed;
            bottom: 150px;
            left: 30px;
            display: grid;
            grid-template-columns: repeat(3, 50px);
            grid-template-rows: repeat(3, 50px);
            gap: 6px;
            z-index: 1001;
            background: rgba(0,0,0,0.85);
            padding: 12px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.15);
            box-shadow: 0 8px 20px rgba(0,0,0,0.4);
            cursor: move;
            touch-action: none;
        }
        
        #wasd-gamepad.dragging {
            opacity: 0.9;
            border-color: #2196F3;
        }
        
        .wasd-btn {
            background: linear-gradient(145deg, rgba(33, 150, 243, 0.3), rgba(33, 150, 243, 0.1));
            border: 1px solid rgba(33, 150, 243, 0.4);
            color: white;
            font-size: 18px;
            font-weight: bold;
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            user-select: none;
            transition: all 0.1s;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        
        .wasd-btn:hover {
            background: linear-gradient(145deg, rgba(33, 150, 243, 0.4), rgba(33, 150, 243, 0.2));
            transform: translateY(-2px);
        }
        
        .wasd-btn:active {
            background: linear-gradient(145deg, rgba(33, 150, 243, 0.8), rgba(33, 150, 243, 0.6));
            transform: translateY(0);
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }
        
        .wasd-btn.pressed {
            background: linear-gradient(145deg, rgba(33, 150, 243, 1), rgba(33, 150, 243, 0.8));
            transform: scale(0.95);
            color: white;
        }
        
        .wasd-btn.w {
            grid-column: 2;
            grid-row: 1;
        }
        
        .wasd-btn.a {
            grid-column: 1;
            grid-row: 2;
        }
        
        .wasd-btn.center {
            grid-column: 2;
            grid-row: 2;
            font-size: 14px;
            background: linear-gradient(145deg, rgba(255, 193, 7, 0.4), rgba(255, 193, 7, 0.2));
            border-color: rgba(255, 193, 7, 0.5);
        }
        
        .wasd-btn.d {
            grid-column: 3;
            grid-row: 2;
        }
        
        .wasd-btn.s {
            grid-column: 2;
            grid-row: 3;
        }
        
        /* Action Buttons */
        #action-buttons {
            position: fixed;
            top: 150px;
            right: 30px;
            display: flex;
            flex-direction: column;
            gap: 10px;
            z-index: 1001;
            cursor: move;
            touch-action: none;
        }
        
        .action-btn {
            background: linear-gradient(145deg, rgba(156, 39, 176, 0.3), rgba(156, 39, 176, 0.1));
            border: 1px solid rgba(156, 39, 176, 0.4);
            color: white;
            font-size: 14px;
            padding: 12px 20px;
            border-radius: 10px;
            cursor: pointer;
            user-select: none;
            transition: all 0.2s;
            min-width: 100px;
            text-align: center;
            backdrop-filter: blur(10px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
        
        .action-btn:hover {
            background: linear-gradient(145deg, rgba(156, 39, 176, 0.4), rgba(156, 39, 176, 0.2));
            transform: translateX(-2px);
        }
        
        .action-btn:active {
            background: linear-gradient(145deg, rgba(156, 39, 176, 0.8), rgba(156, 39, 176, 0.6));
            transform: translateX(0);
        }
        
        .action-btn.pressed {
            background: linear-gradient(145deg, rgba(156, 39, 176, 1), rgba(156, 39, 176, 0.8));
            transform: scale(0.95);
        }
        
        /* Virtual Keyboard */
        #virtual-keyboard {
            position: fixed;
            bottom: 200px;
            left: 50%;
            transform: translateX(-50%);
            display: grid;
            grid-template-columns: repeat(6, 60px);
            gap: 5px;
            z-index: 1001;
            background: rgba(0,0,0,0.9);
            padding: 15px;
            border-radius: 15px;
            backdrop-filter: blur(15px);
            border: 1px solid rgba(255,255,255,0.15);
            box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            cursor: move;
            touch-action: none;
        }
        
        .key {
            background: linear-gradient(145deg, rgba(255,255,255,0.15), rgba(255,255,255,0.05));
            color: white;
            border: 1px solid rgba(255, 255, 255, 0.2);
            padding: 12px 5px;
            border-radius: 8px;
            cursor: pointer;
            text-align: center;
            font-size: 12px;
            transition: all 0.1s;
            user-select: none;
        }
        
        .key:hover {
            background: linear-gradient(145deg, rgba(255,255,255,0.25), rgba(255,255,255,0.15));
            transform: translateY(-2px);
        }
        
        .key:active {
            background: linear-gradient(145deg, rgba(76, 175, 80, 0.6), rgba(76, 175, 80, 0.4));
            transform: translateY(0);
        }
        
        .key.pressed {
            background: linear-gradient(145deg, rgba(76, 175, 80, 0.9), rgba(76, 175, 80, 0.7));
            transform: scale(0.95);
        }
        
        .key.space {
            grid-column: span 2;
            font-size: 11px;
        }
        
        .key.enter {
            background: linear-gradient(145deg, rgba(76, 175, 80, 0.4), rgba(76, 175, 80, 0.2));
            border-color: rgba(76, 175, 80, 0.5);
        }
        
        .key.escape {
            background: linear-gradient(145deg, rgba(244, 67, 54, 0.4), rgba(244, 67, 54, 0.2));
            border-color: rgba(244, 67, 54, 0.5);
        }
        
        .key.shift {
            background: linear-gradient(145deg, rgba(33, 150, 243, 0.4), rgba(33, 150, 243, 0.2));
            border-color: rgba(33, 150, 243, 0.5);
        }
        
        .key.ctrl {
            background: linear-gradient(145deg, rgba(255, 152, 0, 0.4), rgba(255, 152, 0, 0.2));
            border-color: rgba(255, 152, 0, 0.5);
        }
        
        .key.alt {
            background: linear-gradient(145deg, rgba(156, 39, 176, 0.4), rgba(156, 39, 176, 0.2));
            border-color: rgba(156, 39, 176, 0.5);
        }
        
        /* Position Lock Indicator */
        .position-lock {
            position: absolute;
            top: -8px;
            right: -8px;
            width: 20px;
            height: 20px;
            background: #4CAF50;
            border-radius: 50%;
            display: none;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 12px;
            z-index: 1002;
            cursor: pointer;
            border: 2px solid white;
        }
        
        .position-lock.active {
            display: flex;
            background: #ff5722;
        }
        
        /* Drag Handle */
        .drag-handle {
            position: absolute;
            top: 5px;
            right: 5px;
            width: 20px;
            height: 20px;
            cursor: move;
            color: rgba(255,255,255,0.5);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 14px;
        }
        
        /* Responsive Design */
        @media (max-width: 768px) {
            #arrow-gamepad,
            #wasd-gamepad {
                grid-template-columns: repeat(3, 45px);
                grid-template-rows: repeat(3, 45px);
                bottom: 120px;
            }
            
            #virtual-keyboard {
                grid-template-columns: repeat(4, 50px);
                bottom: 180px;
            }
            
            #settings-panel {
                width: 300px;
                right: 10px;
                bottom: 90px;
            }
            
            .action-btn {
                min-width: 80px;
                padding: 10px 15px;
                font-size: 13px;
            }
            
            .key {
                padding: 10px 4px;
                font-size: 11px;
            }
            
            .arrow-btn, .wasd-btn {
                font-size: 16px;
            }
        }
        
        @media (max-width: 480px) {
            #arrow-gamepad,
            #wasd-gamepad {
                grid-template-columns: repeat(3, 40px);
                grid-template-rows: repeat(3, 40px);
                bottom: 100px;
                gap: 4px;
                padding: 8px;
            }
            
            #virtual-keyboard {
                grid-template-columns: repeat(3, 45px);
                bottom: 160px;
                padding: 10px;
            }
            
            #settings-panel {
                width: 280px;
                bottom: 80px;
            }
            
            .action-btn {
                min-width: 70px;
                padding: 8px 12px;
                font-size: 12px;
            }
            
            .key {
                padding: 8px 3px;
                font-size: 10px;
            }
            
            .arrow-btn, .wasd-btn {
                font-size: 14px;
            }
        }
    </style>
</head>
<body>
    <div id="loading">Loading Ruffle Player...</div>
    <div id="fps-display">FPS: --</div>
    <div id="ruffle-container"></div>
    
    <!-- Virtual Cursor -->
    <div id="virtual-cursor"></div>
    
    <!-- Control Panel Container -->
    <div id="control-panel">
        <button id="settings-toggle" class="control-btn" onclick="toggleSettings()">⚙️ Settings</button>
        <button id="toggle-arrows" class="control-btn" onclick="toggleArrows()">⬆️ Arrows</button>
        <button id="toggle-wasd" class="control-btn" onclick="toggleWASD()">🎮 WASD</button>
        <button id="toggle-actions" class="control-btn" onclick="toggleActions()">🔘 Actions</button>
        <button id="toggle-keyboard" class="control-btn" onclick="toggleKeyboard()">⌨️ Keyboard</button>
    </div>
    
    <!-- Settings Panel -->
    <div id="settings-panel">
        <div class="settings-header">
            <h3>Emulator Settings</h3>
            <button class="close-btn" onclick="toggleSettings()">×</button>
        </div>
        
        <div class="setting-group">
            <h4>Control Visibility</h4>
            <div class="setting-item">
                <label>
                    <input type="checkbox" id="show-cursor" checked>
                    Virtual Cursor
                </label>
                <div class="checkbox-container">
                    <input type="checkbox" id="lock-cursor-pos" onchange="toggleLockPosition('cursor')">
                    <label for="lock-cursor-pos" style="font-size: 12px; opacity: 0.8;">Lock Position</label>
                </div>
            </div>
            <div class="setting-item">
                <label>
                    <input type="checkbox" id="show-arrows" checked onchange="toggleControl('arrows')">
                    Arrow Keys Gamepad
                </label>
                <div class="checkbox-container">
                    <input type="checkbox" id="lock-arrows-pos" onchange="toggleLockPosition('arrows')">
                    <label for="lock-arrows-pos" style="font-size: 12px; opacity: 0.8;">Lock Position</label>
                </div>
            </div>
            <div class="setting-item">
                <label>
                    <input type="checkbox" id="show-wasd" onchange="toggleControl('wasd')">
                    WASD Gamepad
                </label>
                <div class="checkbox-container">
                    <input type="checkbox" id="lock-wasd-pos" onchange="toggleLockPosition('wasd')">
                    <label for="lock-wasd-pos" style="font-size: 12px; opacity: 0.8;">Lock Position</label>
                </div>
            </div>
            <div class="setting-item">
                <label>
                    <input type="checkbox" id="show-actions" onchange="toggleControl('actions')">
                    Action Buttons
                </label>
                <div class="checkbox-container">
                    <input type="checkbox" id="lock-actions-pos" onchange="toggleLockPosition('actions')">
                    <label for="lock-actions-pos" style="font-size: 12px; opacity: 0.8;">Lock Position</label>
                </div>
            </div>
            <div class="setting-item">
                <label>
                    <input type="checkbox" id="show-keyboard" onchange="toggleControl('keyboard')">
                    Virtual Keyboard
                </label>
                <div class="checkbox-container">
                    <input type="checkbox" id="lock-keyboard-pos" onchange="toggleLockPosition('keyboard')">
                    <label for="lock-keyboard-pos" style="font-size: 12px; opacity: 0.8;">Lock Position</label>
                </div>
            </div>
        </div>
        
        <div class="setting-group">
            <h4>Display Settings</h4>
            <div class="setting-item">
                <label for="show-fps">FPS Display</label>
                <input type="checkbox" id="show-fps" checked>
            </div>
            <div class="setting-item">
                <label for="bg-color">Background Color</label>
                <input type="color" id="bg-color" value="#000000">
            </div>
            <div class="setting-item">
                <label for="scale-mode">Scale Mode</label>
                <select id="scale-mode">
                    <option value="showAll">Show All</option>
                    <option value="noBorder">No Border</option>
                    <option value="exactFit">Exact Fit</option>
                    <option value="noScale">No Scale</option>
                </select>
            </div>
        </div>
        
        <div class="setting-group">
            <h4>Performance</h4>
            <div class="setting-item">
                <label for="fps-limit">FPS Limit</label>
                <select id="fps-limit">
                    <option value="30">30 FPS</option>
                    <option value="60" selected>60 FPS</option>
                    <option value="75">75 FPS</option>
                    <option value="120">120 FPS</option>
                    <option value="144">144 FPS</option>
                    <option value="0">Unlimited</option>
                </select>
            </div>
            <div class="setting-item">
                <label for="render-quality">Render Quality</label>
                <select id="render-quality">
                    <option value="low">Low</option>
                    <option value="medium">Medium</option>
                    <option value="high" selected>High</option>
                    <option value="best">Best</option>
                </select>
            </div>
        </div>
        
        <div class="setting-group">
            <h4>Input Settings</h4>
            <div class="setting-item">
                <label for="click-sound">Click Sound</label>
                <input type="checkbox" id="click-sound">
            </div>
            <div class="setting-item">
                <label for="drag-mode">Cursor Drag Mode</label>
                <input type="checkbox" id="drag-mode">
            </div>
            <div class="setting-item">
                <label for="vibration">Touch Vibration</label>
                <input type="checkbox" id="vibration">
            </div>
            <div class="setting-item">
                <label for="auto-hide">Auto-hide Controls</label>
                <input type="checkbox" id="auto-hide">
            </div>
        </div>
        
        <div class="setting-group">
            <h4>Key Mapping</h4>
            <div class="setting-item">
                <label for="arrow-keys-enable">Enable Arrow Keys</label>
                <input type="checkbox" id="arrow-keys-enable" checked>
            </div>
            <div class="setting-item">
                <label for="wasd-keys-enable">Enable WASD Keys</label>
                <input type="checkbox" id="wasd-keys-enable">
            </div>
            <div class="setting-item">
                <label for="action-keys-enable">Enable Action Keys</label>
                <input type="checkbox" id="action-keys-enable" checked>
            </div>
        </div>
        
        <div style="margin-top: 20px;">
            <button onclick="resetSettings()" style="width: 100%; padding: 12px; background: linear-gradient(145deg, rgba(255,87,34,0.3), rgba(255,87,34,0.1)); border: 1px solid rgba(255,87,34,0.5); color: white; border-radius: 8px; cursor: pointer;">
                Reset to Default
            </button>
        </div>
    </div>
    
    <!-- Arrow Keys Gamepad -->
    <div id="arrow-gamepad">
        <div class="position-lock" id="lock-arrows" onclick="toggleLockPosition('arrows')">🔒</div>
        <div class="drag-handle">⋮⋮</div>
        <div class="arrow-btn up" data-key="38">↑</div>
        <div class="arrow-btn left" data-key="37">←</div>
        <div class="arrow-btn center" onclick="simulateClick()">CLICK</div>
        <div class="arrow-btn right" data-key="39">→</div>
        <div class="arrow-btn down" data-key="40">↓</div>
    </div>
    
    <!-- WASD Gamepad -->
    <div id="wasd-gamepad" style="display: none;">
        <div class="position-lock" id="lock-wasd" onclick="toggleLockPosition('wasd')">🔒</div>
        <div class="drag-handle">⋮⋮</div>
        <div class="wasd-btn w" data-key="87">W</div>
        <div class="wasd-btn a" data-key="65">A</div>
        <div class="wasd-btn center" onclick="simulateClick()">CLICK</div>
        <div class="wasd-btn d" data-key="68">D</div>
        <div class="wasd-btn s" data-key="83">S</div>
    </div>
    
    <!-- Action Buttons -->
    <div id="action-buttons" style="display: none;">
        <div class="position-lock" id="lock-actions" onclick="toggleLockPosition('actions')">🔒</div>
        <div class="drag-handle">⋮⋮</div>
        <button class="action-btn" data-key="32">SPACE</button>
        <button class="action-btn" data-key="13">ENTER</button>
        <button class="action-btn" data-key="27">ESC</button>
        <button class="action-btn" data-key="16">SHIFT</button>
        <button class="action-btn" data-key="17">CTRL</button>
    </div>
    
    <!-- Virtual Keyboard -->
    <div id="virtual-keyboard" style="display: none;">
        <div class="position-lock" id="lock-keyboard" onclick="toggleLockPosition('keyboard')">🔒</div>
        <div class="drag-handle">⋮⋮</div>
        <div class="key space" data-key="32">SPACE</div>
        <div class="key enter" data-key="13">ENTER</div>
        <div class="key escape" data-key="27">ESC</div>
        <div class="key shift" data-key="16">SHIFT</div>
        <div class="key ctrl" data-key="17">CTRL</div>
        <div class="key alt" data-key="18">ALT</div>
        <div class="key" data-key="81">Q</div>
        <div class="key" data-key="69">E</div>
        <div class="key" data-key="82">R</div>
        <div class="key" data-key="70">F</div>
        <div class="key" data-key="90">Z</div>
        <div class="key" data-key="88">X</div>
    </div>
    
    <script src="https://unpkg.com/@ruffle-rs/ruffle"></script>
    <script>
        let player = null;
        let ruffle = null;
        let fps = 0;
        let frameCount = 0;
        let lastTime = performance.now();
        let cursorVisible = true;
        let isDragging = false;
        let cursorX = window.innerWidth / 2;
        let cursorY = window.innerHeight / 2;
        let activeKeyPresses = new Set();
        let swfWidth = 800;
        let swfHeight = 600;
        let swfAspectRatio = 4/3;
        
        // Position lock states
        const positionLocks = {
            arrows: false,
            wasd: false,
            actions: false,
            keyboard: false,
            cursor: false
        };
        
        // Control positions storage
        const controlPositions = {
            arrows: { x: null, y: null },
            wasd: { x: null, y: null },
            actions: { x: null, y: null },
            keyboard: { x: null, y: null }
        };
        
        // FPS Counter
        function updateFPS() {
            frameCount++;
            const currentTime = performance.now();
            if (currentTime - lastTime >= 1000) {
                fps = Math.round((frameCount * 1000) / (currentTime - lastTime));
                document.getElementById('fps-display').textContent = \`FPS: \${fps}\`;
                frameCount = 0;
                lastTime = currentTime;
            }
            requestAnimationFrame(updateFPS);
        }
        
        // Virtual Cursor
        const virtualCursor = document.getElementById('virtual-cursor');
        
        function updateCursorPosition(x, y) {
            if (positionLocks.cursor) return;
            
            cursorX = x;
            cursorY = y;
            virtualCursor.style.left = \`\${x}px\`;
            virtualCursor.style.top = \`\${y}px\`;
        }
        
        function showClickAnimation() {
            virtualCursor.classList.add('clicking');
            setTimeout(() => {
                virtualCursor.classList.remove('clicking');
            }, 200);
            
            if (document.getElementById('click-sound').checked) {
                const clickSound = new Audio('data:audio/wav;base64,UklGRigAAABXQVZFZm10IBIAAAABAAEARKwAAIhYAQACABAAZGF0YQQAAAAAAA==');
                clickSound.volume = 0.3;
                clickSound.play();
            }
            
            if (document.getElementById('vibration').checked && navigator.vibrate) {
                navigator.vibrate(50);
            }
        }
        
        // Simulate mouse events
        function simulateClick() {
            const event = new MouseEvent('click', {
                view: window,
                bubbles: true,
                cancelable: true,
                clientX: cursorX,
                clientY: cursorY
            });
            
            const element = document.elementFromPoint(cursorX, cursorY);
            if (element) {
                element.dispatchEvent(event);
            }
            showClickAnimation();
        }
        
        // Keyboard simulation with hold support
        function startKeyPress(keyCode) {
            if (activeKeyPresses.has(keyCode)) return;
            
            activeKeyPresses.add(keyCode);
            const event = new KeyboardEvent('keydown', {
                keyCode: keyCode,
                bubbles: true,
                repeat: false
            });
            document.dispatchEvent(event);
            
            // Visual feedback
            const btn = document.querySelector(\`.arrow-btn[data-key="\${keyCode}"], .wasd-btn[data-key="\${keyCode}"], .action-btn[data-key="\${keyCode}"], .key[data-key="\${keyCode}"]\`);
            if (btn) btn.classList.add('pressed');
        }
        
        function stopKeyPress(keyCode) {
            if (!activeKeyPresses.has(keyCode)) return;
            
            activeKeyPresses.delete(keyCode);
            const event = new KeyboardEvent('keyup', {
                keyCode: keyCode,
                bubbles: true
            });
            document.dispatchEvent(event);
            
            // Remove visual feedback
            const btn = document.querySelector(\`.arrow-btn[data-key="\${keyCode}"], .wasd-btn[data-key="\${keyCode}"], .action-btn[data-key="\${keyCode}"], .key[data-key="\${keyCode}"]\`);
            if (btn) btn.classList.remove('pressed');
        }
        
        // Toggle functions
        function toggleSettings() {
            const panel = document.getElementById('settings-panel');
            panel.style.display = panel.style.display === 'block' ? 'none' : 'block';
            updateToggleButtons();
        }
        
        function toggleArrows() {
            const arrows = document.getElementById('arrow-gamepad');
            const isVisible = arrows.style.display !== 'none';
            arrows.style.display = isVisible ? 'none' : 'block';
            document.getElementById('show-arrows').checked = !isVisible;
            updateToggleButtons();
            saveControlVisibility();
        }
        
        function toggleWASD() {
            const wasd = document.getElementById('wasd-gamepad');
            const isVisible = wasd.style.display !== 'none';
            wasd.style.display = isVisible ? 'none' : 'block';
            document.getElementById('show-wasd').checked = !isVisible;
            updateToggleButtons();
            saveControlVisibility();
        }
        
        function toggleActions() {
            const actions = document.getElementById('action-buttons');
            const isVisible = actions.style.display !== 'none';
            actions.style.display = isVisible ? 'none' : 'flex';
            document.getElementById('show-actions').checked = !isVisible;
            updateToggleButtons();
            saveControlVisibility();
        }
        
        function toggleKeyboard() {
            const keyboard = document.getElementById('virtual-keyboard');
            const isVisible = keyboard.style.display !== 'none';
            keyboard.style.display = isVisible ? 'none' : 'grid';
            document.getElementById('show-keyboard').checked = !isVisible;
            updateToggleButtons();
            saveControlVisibility();
        }
        
        function toggleControl(type) {
            switch(type) {
                case 'arrows':
                    toggleArrows();
                    break;
                case 'wasd':
                    toggleWASD();
                    break;
                case 'actions':
                    toggleActions();
                    break;
                case 'keyboard':
                    toggleKeyboard();
                    break;
            }
        }
        
        function updateToggleButtons() {
            const arrowsBtn = document.getElementById('toggle-arrows');
            const wasdBtn = document.getElementById('toggle-wasd');
            const actionsBtn = document.getElementById('toggle-actions');
            const keyboardBtn = document.getElementById('toggle-keyboard');
            
            arrowsBtn.classList.toggle('active', document.getElementById('arrow-gamepad').style.display !== 'none');
            wasdBtn.classList.toggle('active', document.getElementById('wasd-gamepad').style.display !== 'none');
            actionsBtn.classList.toggle('active', document.getElementById('action-buttons').style.display !== 'none');
            keyboardBtn.classList.toggle('active', document.getElementById('virtual-keyboard').style.display !== 'none');
        }
        
        // Position lock functions
        function toggleLockPosition(type) {
            positionLocks[type] = !positionLocks[type];
            const lockElement = document.getElementById(\`lock-\${type}\`);
            lockElement.classList.toggle('active', positionLocks[type]);
            
            // Save lock state
            localStorage.setItem(\`lock_\${type}\`, positionLocks[type]);
            
            // Update drag handle visibility
            const dragHandle = lockElement.parentElement.querySelector('.drag-handle');
            if (dragHandle) {
                dragHandle.style.display = positionLocks[type] ? 'none' : 'flex';
            }
            
            // If unlocking and no position saved, set default position
            if (!positionLocks[type] && !controlPositions[type].x) {
                setDefaultPosition(type);
            }
        }
        
        function setDefaultPosition(type) {
            const element = document.getElementById(\`\${type}-gamepad\`) || 
                            document.getElementById(\`\${type}-buttons\`) || 
                            document.getElementById(\`virtual-keyboard\`);
            
            if (!element) return;
            
            switch(type) {
                case 'arrows':
                    element.style.bottom = '150px';
                    element.style.right = '30px';
                    element.style.left = 'auto';
                    break;
                case 'wasd':
                    element.style.bottom = '150px';
                    element.style.left = '30px';
                    element.style.right = 'auto';
                    break;
                case 'actions':
                    element.style.top = '150px';
                    element.style.right = '30px';
                    element.style.left = 'auto';
                    break;
                case 'keyboard':
                    element.style.bottom = '200px';
                    element.style.left = '50%';
                    element.style.right = 'auto';
                    element.style.transform = 'translateX(-50%)';
                    break;
            }
            
            controlPositions[type].x = element.style.left;
            controlPositions[type].y = element.style.top;
        }
        
        // Settings Management
        function resetSettings() {
            // Reset visibility
            document.getElementById('show-cursor').checked = true;
            document.getElementById('show-arrows').checked = true;
            document.getElementById('show-wasd').checked = false;
            document.getElementById('show-actions').checked = false;
            document.getElementById('show-keyboard').checked = false;
            
            // Reset display settings
            document.getElementById('show-fps').checked = true;
            document.getElementById('bg-color').value = '#000000';
            document.getElementById('scale-mode').value = 'showAll';
            
            // Reset performance
            document.getElementById('fps-limit').value = '60';
            document.getElementById('render-quality').value = 'high';
            
            // Reset input settings
            document.getElementById('click-sound').checked = false;
            document.getElementById('drag-mode').checked = false;
            document.getElementById('vibration').checked = false;
            document.getElementById('auto-hide').checked = false;
            
            // Reset key mapping
            document.getElementById('arrow-keys-enable').checked = true;
            document.getElementById('wasd-keys-enable').checked = false;
            document.getElementById('action-keys-enable').checked = true;
            
            // Reset position locks
            Object.keys(positionLocks).forEach(type => {
                positionLocks[type] = false;
                const lockElement = document.getElementById(\`lock-\${type}\`);
                if (lockElement) {
                    lockElement.classList.remove('active');
                }
                const dragHandle = lockElement?.parentElement.querySelector('.drag-handle');
                if (dragHandle) {
                    dragHandle.style.display = 'flex';
                }
            });
            
            applySettings();
            resetControlPositions();
            alert('All settings have been reset to default');
        }
        
        function resetControlPositions() {
            // Reset all control positions to default
            setDefaultPosition('arrows');
            setDefaultPosition('wasd');
            setDefaultPosition('actions');
            setDefaultPosition('keyboard');
            
            // Reset cursor position
            cursorX = window.innerWidth / 2;
            cursorY = window.innerHeight / 2;
            updateCursorPosition(cursorX, cursorY);
        }
        
        function applySettings() {
            // Cursor visibility
            virtualCursor.style.display = 
                document.getElementById('show-cursor').checked ? 'block' : 'none';
            cursorVisible = document.getElementById('show-cursor').checked;
            
            // FPS display
            document.getElementById('fps-display').style.display = 
                document.getElementById('show-fps').checked ? 'block' : 'none';
            
            // Apply visibility from checkboxes
            document.getElementById('arrow-gamepad').style.display = 
                document.getElementById('show-arrows').checked ? 'block' : 'none';
            document.getElementById('wasd-gamepad').style.display = 
                document.getElementById('show-wasd').checked ? 'block' : 'none';
            document.getElementById('action-buttons').style.display = 
                document.getElementById('show-actions').checked ? 'flex' : 'none';
            document.getElementById('virtual-keyboard').style.display = 
                document.getElementById('show-keyboard').checked ? 'grid' : 'none';
            
            // Update toggle buttons
            updateToggleButtons();
            
            // Update Ruffle config
            if (player && player.config) {
                player.config.quality = document.getElementById('render-quality').value;
                player.config.backgroundColor = document.getElementById('bg-color').value;
                player.config.letterbox = document.getElementById('scale-mode').value === 'showAll' ? 'on' : 'off';
                player.config.scale = document.getElementById('scale-mode').value;
                
                // Update SWF container background
                document.getElementById('ruffle-container').style.backgroundColor = 
                    document.getElementById('bg-color').value;
            }
            
            saveControlVisibility();
        }
        
        function saveControlVisibility() {
            const visibility = {
                arrows: document.getElementById('show-arrows').checked,
                wasd: document.getElementById('show-wasd').checked,
                actions: document.getElementById('show-actions').checked,
                keyboard: document.getElementById('show-keyboard').checked
            };
            localStorage.setItem('control_visibility', JSON.stringify(visibility));
        }
        
        function loadControlVisibility() {
            const saved = localStorage.getItem('control_visibility');
            if (saved) {
                const visibility = JSON.parse(saved);
                document.getElementById('show-arrows').checked = visibility.arrows;
                document.getElementById('show-wasd').checked = visibility.wasd;
                document.getElementById('show-actions').checked = visibility.actions;
                document.getElementById('show-keyboard').checked = visibility.keyboard;
            }
        }
        
        // Make draggable function
        function makeDraggable(element, type) {
            let pos1 = 0, pos2 = 0, pos3 = 0, pos4 = 0;
            
            element.onmousedown = dragMouseDown;
            element.ontouchstart = dragTouchStart;
            
            function dragMouseDown(e) {
                if (positionLocks[type]) return;
                
                e = e || window.event;
                e.preventDefault();
                pos3 = e.clientX;
                pos4 = e.clientY;
                element.classList.add('dragging');
                document.onmouseup = closeDragElement;
                document.onmousemove = elementDrag;
            }
            
            function dragTouchStart(e) {
                if (positionLocks[type]) return;
                
                e.preventDefault();
                if (e.touches.length === 1) {
                    pos3 = e.touches[0].clientX;
                    pos4 = e.touches[0].clientY;
                    element.classList.add('dragging');
                    document.ontouchend = closeDragElement;
                    document.ontouchmove = elementTouchDrag;
                }
            }
            
            function elementDrag(e) {
                e = e || window.event;
                e.preventDefault();
                pos1 = pos3 - e.clientX;
                pos2 = pos4 - e.clientY;
                pos3 = e.clientX;
                pos4 = e.clientY;
                
                const newTop = element.offsetTop - pos2;
                const newLeft = element.offsetLeft - pos1;
                
                element.style.top = \`\${newTop}px\`;
                element.style.left = \`\${newLeft}px\`;
                element.style.right = 'auto';
                element.style.bottom = 'auto';
                element.style.transform = 'none';
                
                // Save position
                controlPositions[type].x = \`\${newLeft}px\`;
                controlPositions[type].y = \`\${newTop}px\`;
            }
            
            function elementTouchDrag(e) {
                e.preventDefault();
                if (e.touches.length === 1) {
                    pos1 = pos3 - e.touches[0].clientX;
                    pos2 = pos4 - e.touches[0].clientY;
                    pos3 = e.touches[0].clientX;
                    pos4 = e.touches[0].clientY;
                    
                    const newTop = element.offsetTop - pos2;
                    const newLeft = element.offsetLeft - pos1;
                    
                    element.style.top = \`\${newTop}px\`;
                    element.style.left = \`\${newLeft}px\`;
                    element.style.right = 'auto';
                    element.style.bottom = 'auto';
                    element.style.transform = 'none';
                    
                    // Save position
                    controlPositions[type].x = \`\${newLeft}px\`;
                    controlPositions[type].y = \`\${newTop}px\`;
                }
            }
            
            function closeDragElement() {
                element.classList.remove('dragging');
                document.onmouseup = null;
                document.onmousemove = null;
                document.ontouchend = null;
                document.ontouchmove = null;
            }
        }
        
        // Initialize Ruffle
        window.RufflePlayer = window.RufflePlayer || {};
        window.RufflePlayer.config = {
            "autoplay": "on",
            "unmuteOverlay": "hidden",
            "backgroundColor": "#000000",
            "warnOnUnsupportedContent": false,
            "letterbox": "on",
            "quality": "high",
            "scale": "showAll",
            "salign": "",
            "forceScale": true,
            "forceAlign": false,
            "frameRate": 60,
            "allowScriptAccess": false,
            "preferredRenderer": "canvas",
            "contextMenu": true,
            "showSwfDownload": false,
            "upgradeToHttps": false,
            "logLevel": "error",
            "menu": true,
            "openUrlMode": "allow",
            "allowNetworking": "all"
        };
        
        // Load SWF
        function loadSWF() {
            ruffle = window.RufflePlayer.newest();
            player = ruffle.createPlayer();
            const container = document.getElementById("ruffle-container");
            container.appendChild(player);
            
            const swfData = "$swfBase64";
            const binary = atob(swfData);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) {
                bytes[i] = binary.charCodeAt(i);
            }
            const blob = new Blob([bytes], {type: "application/x-shockwave-flash"});
            const url = URL.createObjectURL(blob);
            
            player.load({
                url: url,
                allowFullscreen: true,
                backgroundColor: "#000000"
            }).then(() => {
                document.getElementById("loading").style.display = "none";
                player.focus();
                
                // Set SWF size
                const ruffleCanvas = container.querySelector('canvas');
                if (ruffleCanvas) {
                    ruffleCanvas.style.cursor = 'none';
                    
                    // Wait a bit for the canvas to render
                    setTimeout(() => {
                        swfWidth = ruffleCanvas.width || 800;
                        swfHeight = ruffleCanvas.height || 600;
                        swfAspectRatio = swfWidth / swfHeight;
                    }, 500);
                }
                
                // Start FPS counter
                updateFPS();
            }).catch(error => {
                console.error("Load error:", error);
                document.getElementById("loading").innerHTML = 
                    "Failed to load SWF file: " + error.message;
            });
        }
        
        // Initialize all controls
        function initializeControls() {
            // Make controls draggable
            makeDraggable(document.getElementById('arrow-gamepad'), 'arrows');
            makeDraggable(document.getElementById('wasd-gamepad'), 'wasd');
            makeDraggable(document.getElementById('action-buttons'), 'actions');
            makeDraggable(document.getElementById('virtual-keyboard'), 'keyboard');
            
            // Add event listeners to control buttons
            document.querySelectorAll('.arrow-btn[data-key], .wasd-btn[data-key], .action-btn[data-key], .key[data-key]').forEach(btn => {
                const keyCode = parseInt(btn.getAttribute('data-key'));
                
                // Mouse events
                btn.addEventListener('mousedown', (e) => {
                    e.preventDefault();
                    startKeyPress(keyCode);
                });
                
                btn.addEventListener('mouseup', () => {
                    stopKeyPress(keyCode);
                });
                
                btn.addEventListener('mouseleave', () => {
                    stopKeyPress(keyCode);
                });
                
                // Touch events
                btn.addEventListener('touchstart', (e) => {
                    e.preventDefault();
                    startKeyPress(keyCode);
                });
                
                btn.addEventListener('touchend', () => {
                    stopKeyPress(keyCode);
                });
                
                btn.addEventListener('touchcancel', () => {
                    stopKeyPress(keyCode);
                });
            });
            
            // Load saved positions
            loadControlVisibility();
            
            // Load saved position locks
            Object.keys(positionLocks).forEach(type => {
                const saved = localStorage.getItem(\`lock_\${type}\`);
                if (saved !== null) {
                    positionLocks[type] = JSON.parse(saved);
                    const lockElement = document.getElementById(\`lock-\${type}\`);
                    if (lockElement) {
                        lockElement.classList.toggle('active', positionLocks[type]);
                        const dragHandle = lockElement.parentElement.querySelector('.drag-handle');
                        if (dragHandle) {
                            dragHandle.style.display = positionLocks[type] ? 'none' : 'flex';
                        }
                    }
                }
            });
        }
        
        // Event Listeners
        document.addEventListener('DOMContentLoaded', () => {
            loadSWF();
            initializeControls();
            resetSettings(); // Apply default settings
            
            // Initialize cursor position
            updateCursorPosition(window.innerWidth / 2, window.innerHeight / 2);
            
            // Mouse and touch events for cursor
            document.addEventListener('mousemove', (e) => {
                if (!document.getElementById('drag-mode').checked && !positionLocks.cursor) {
                    updateCursorPosition(e.clientX, e.clientY);
                }
            });
            
            document.addEventListener('touchmove', (e) => {
                e.preventDefault();
                if (e.touches.length > 0 && !document.getElementById('drag-mode').checked && !positionLocks.cursor) {
                    const touch = e.touches[0];
                    updateCursorPosition(touch.clientX, touch.clientY);
                }
            }, { passive: false });
            
            // Click events
            document.addEventListener('click', (e) => {
                // Skip if clicking on control elements
                if (e.target.closest('#control-panel') || 
                    e.target.closest('#settings-panel') ||
                    e.target.closest('#arrow-gamepad') ||
                    e.target.closest('#wasd-gamepad') ||
                    e.target.closest('#action-buttons') ||
                    e.target.closest('#virtual-keyboard')) {
                    return;
                }
                if (cursorVisible && !positionLocks.cursor) {
                    updateCursorPosition(e.clientX, e.clientY);
                    showClickAnimation();
                }
            });
            
            // Drag mode for cursor
            virtualCursor.addEventListener('mousedown', (e) => {
                if (document.getElementById('drag-mode').checked && !positionLocks.cursor) {
                    isDragging = true;
                    e.preventDefault();
                }
            });
            
            document.addEventListener('mousemove', (e) => {
                if (isDragging && document.getElementById('drag-mode').checked && !positionLocks.cursor) {
                    updateCursorPosition(e.clientX, e.clientY);
                }
            });
            
            document.addEventListener('mouseup', () => {
                isDragging = false;
            });
            
            // Keyboard controls with enable/disable check
            document.addEventListener("keydown", function(e) {
                const arrowKeysEnabled = document.getElementById('arrow-keys-enable').checked;
                const wasdKeysEnabled = document.getElementById('wasd-keys-enable').checked;
                const actionKeysEnabled = document.getElementById('action-keys-enable').checked;
                
                let shouldPrevent = false;
                
                // Check arrow keys (37-40)
                if (arrowKeysEnabled && e.keyCode >= 37 && e.keyCode <= 40) {
                    shouldPrevent = true;
                }
                
                // Check WASD keys (65, 68, 87, 83)
                if (wasdKeysEnabled && [65, 68, 87, 83].includes(e.keyCode)) {
                    shouldPrevent = true;
                }
                
                // Check action keys (32, 13, 27, 16, 17, 18)
                if (actionKeysEnabled && [32, 13, 27, 16, 17, 18].includes(e.keyCode)) {
                    shouldPrevent = true;
                }
                
                if (shouldPrevent) {
                    e.preventDefault();
                    e.stopPropagation();
                    startKeyPress(e.keyCode);
                }
            }, true);
            
            document.addEventListener("keyup", function(e) {
                stopKeyPress(e.keyCode);
            }, true);
            
            // Settings change listeners
            document.querySelectorAll('#settings-panel input, #settings-panel select').forEach(element => {
                element.addEventListener('change', applySettings);
            });
            
            // Clean up on blur
            window.addEventListener('blur', () => {
                activeKeyPresses.forEach(keyCode => stopKeyPress(keyCode));
                activeKeyPresses.clear();
            });
            
            // Auto-hide controls
            let hideTimeout;
            document.addEventListener('mousemove', () => {
                if (document.getElementById('auto-hide').checked) {
                    clearTimeout(hideTimeout);
                    document.getElementById('control-panel').style.opacity = '1';
                    hideTimeout = setTimeout(() => {
                        document.getElementById('control-panel').style.opacity = '0.3';
                    }, 3000);
                }
            });
        });
        
        // Handle window resize
        window.addEventListener('resize', () => {
            // Adjust cursor position
            if (cursorX > window.innerWidth) cursorX = window.innerWidth - 10;
            if (cursorY > window.innerHeight) cursorY = window.innerHeight - 10;
            if (!positionLocks.cursor) {
                updateCursorPosition(cursorX, cursorY);
            }
            
            // Adjust controls that are locked to edges
            if (!positionLocks.arrows && !controlPositions.arrows.x) {
                setDefaultPosition('arrows');
            }
            if (!positionLocks.wasd && !controlPositions.wasd.x) {
                setDefaultPosition('wasd');
            }
            if (!positionLocks.actions && !controlPositions.actions.x) {
                setDefaultPosition('actions');
            }
            if (!positionLocks.keyboard && !controlPositions.keyboard.x) {
                setDefaultPosition('keyboard');
            }
        });
        
        // Prevent context menu on game controls
        document.addEventListener('contextmenu', (e) => {
            if (e.target.closest('#arrow-gamepad') || 
                e.target.closest('#wasd-gamepad') ||
                e.target.closest('#action-buttons') ||
                e.target.closest('#virtual-keyboard') ||
                e.target.closest('#control-panel')) {
                e.preventDefault();
            }
        });
    </script>
</body>
</html>
''';

      await _controller.loadHtmlString(ruffleHtml);
    } catch (e) {
      print('Error loading Ruffle content: $e');
      await _controller.loadHtmlString('''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Error</title>
    <style>
        body { margin: 0; padding: 20px; background: #0f0f1a; color: white; font-family: Arial; }
        .error { color: #ff4757; }
    </style>
</head>
<body>
    <h1>Error Loading SWF</h1>
    <p class="error">${e.toString()}</p>
</body>
</html>
''');
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _reloadGame() async {
    setState(() {
      _isLoading = true;
    });
    await _controller.reload();
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            
            if (_isLoading)
              Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF2D6AE0),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Loading game...',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
            
            if (!_isLoading)
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                        onPressed: _goBack,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.gameData.displayName,
                              style: const TextStyle(
                                color: Colors.white, 
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Text(
                              '${widget.gameData.fileType.toUpperCase()} • ${widget.gameData.playCount} plays',
                              style: const TextStyle(
                                color: Colors.grey, 
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: Icon(
                          _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: _toggleFullscreen,
                        tooltip: _isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 24),
                        onPressed: _reloadGame,
                        tooltip: 'Reload Game',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}