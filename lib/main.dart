import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI South Indian Diet Bot',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        fontFamily: 'Roboto',
      ),
      home: PureAIDietBotScreen(),
    );
  }
}

// ============ CLEAN GROQ SERVICE ============
class PureAIGroqService {
  static String get API_KEY => dotenv.env['GROQ_API_KEY'] ?? '';
  static const String BASE_URL = 'https://api.groq.com/openai/v1/chat/completions';

  static Future<Map<String, dynamic>> getAIResponseWithActions(
    String userMessage,
    List<String> conversationHistory,
    List<String> currentPantry,
    List<String> currentMealPlan,
  ) async {
    try {
      print('🤖 Calling Groq AI...');
      
      String conversationContext = conversationHistory.take(6).join('\n');
      String pantryContext = currentPantry.isEmpty
          ? "Empty pantry"
          : "Current pantry: ${currentPantry.join(', ')}";
      String planContext = currentMealPlan.isEmpty
          ? "No meal plan yet"
          : "Current meal suggestions: ${currentMealPlan.join(', ')}";

      final response = await http.post(
        Uri.parse(BASE_URL),
        headers: {
          'Authorization': 'Bearer $API_KEY',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'llama3-70b-8192',
          'messages': [
            {
              'role': 'system',
              'content': '''You are Ruchi, an intelligent South Indian food expert who understands ALL Indian languages.

IMPORTANT: Always respond with natural conversation AND structured JSON actions in this EXACT format:

{
  "response": "Your natural response here",
  "actions": {
    "pantry_add": ["ingredient1", "ingredient2"],
    "pantry_remove": ["ingredient3"],
    "meals_suggest": [
      {
        "name": "Vankaya Curry",
        "ingredients": ["brinjal", "onion", "tomato", "oil", "spices"],
        "prep_time": "25 minutes",
        "difficulty": "Medium",
        "steps": ["Step 1: Wash and chop brinjal", "Step 2: Heat oil in pan", "Step 3: Add onions", "Step 4: Add tomatoes", "Step 5: Add brinjal and spices", "Step 6: Cook until tender"],
        "description": "Delicious Telugu-style brinjal curry",
        "region": "Telugu",
        "serves": "4 people",
        "tips": ["Use fresh vegetables", "Adjust spices to taste"]
      }
    ],
    "preferences_update": ["preference1"]
  }
}

RULES:
- Understand ingredients in any Indian language (Telugu, Tamil, Malayalam, etc.)
- When user mentions having/buying ingredients → add to pantry_add
- When user mentions finishing/running out → add to pantry_remove
- Always suggest 1-2 detailed recipes with complete cooking steps → add to meals_suggest
- Track food preferences → add to preferences_update

Always include complete recipe details with realistic cooking steps!'''
            },
            {
              'role': 'user',
              'content': '''Context:
Conversation: $conversationContext
$pantryContext
$planContext

User message: "$userMessage"

Respond with natural conversation AND detailed JSON recipe actions.'''
            }
          ],
          'max_tokens': 700,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String aiResponse = data['choices'][0]['message']['content'];
        print('✅ AI Response received');
        return _parseAIResponse(aiResponse);
      } else {
        print('❌ Groq Error: ${response.statusCode}');
        return _getFallbackResponse(userMessage);
      }
    } catch (e) {
      print('🔥 Error: $e');
      return _getFallbackResponse(userMessage);
    }
  }

  static Map<String, dynamic> _parseAIResponse(String aiResponse) {
    try {
      int jsonStart = aiResponse.indexOf('{');
      int jsonEnd = aiResponse.lastIndexOf('}') + 1;
      
      if (jsonStart != -1 && jsonEnd > jsonStart) {
        String jsonPart = aiResponse.substring(jsonStart, jsonEnd);
        Map<String, dynamic> parsed = jsonDecode(jsonPart);
        
        return {
          'response': parsed['response'] ?? aiResponse,
          'actions': parsed['actions'] ?? {},
        };
      } else {
        return _smartFallbackParsing(aiResponse);
      }
    } catch (e) {
      print('⚠️ JSON Parse Error: $e');
      return _smartFallbackParsing(aiResponse);
    }
  }

  static Map<String, dynamic> _smartFallbackParsing(String text) {
    List<String> pantryAdd = [];
    List<dynamic> mealsAdd = [];
    String lowerText = text.toLowerCase();
    
    // Basic ingredient detection
    Map<String, String> ingredients = {
      'rice': 'rice', 'annam': 'rice', 'arisi': 'rice',
      'dal': 'dal', 'pappu': 'dal', 'paruppu': 'dal',
      'tomato': 'tomato', 'thakkali': 'tomato', 'tamata': 'tomato',
      'onion': 'onion', 'ullipaya': 'onion', 'vengayam': 'onion',
      'brinjal': 'brinjal', 'vankaya': 'brinjal', 'kathirikai': 'brinjal',
      'coconut': 'coconut', 'kobbari': 'coconut', 'thengai': 'coconut',
    };
    
    for (String key in ingredients.keys) {
      if (lowerText.contains(key)) {
        pantryAdd.add(ingredients[key]!);
      }
    }
    
    // Add sample recipes if mentioned
    if (lowerText.contains('curry')) {
      mealsAdd.add({
        'name': 'Vegetable Curry',
        'ingredients': ['vegetables', 'onion', 'tomato', 'spices'],
        'prep_time': '25 minutes',
        'difficulty': 'Medium',
        'steps': ['Heat oil', 'Add onions', 'Add tomatoes', 'Add vegetables', 'Cook until done'],
        'description': 'Delicious mixed vegetable curry',
        'region': 'General',
        'serves': '4 people',
        'tips': ['Use fresh ingredients']
      });
    }

    return {
      'response': text,
      'actions': {
        'pantry_add': pantryAdd,
        'meals_suggest': mealsAdd,
      },
    };
  }

  static Map<String, dynamic> _getFallbackResponse(String userMessage) {
    return {
      'response': "I understand you're talking about food! Tell me what ingredients you have or what you'd like to cook, and I'll help you create delicious South Indian meals with complete recipes! 🍛",
      'actions': {},
    };
  }
}

// ============ DATA MANAGER ============
class PureAIDataManager {
  List<String> pantryItems = [];
  List<Map<String, dynamic>> mealSuggestions = [];
  List<String> userPreferences = [];

  Future<void> loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      pantryItems = prefs.getStringList('pantryItems') ?? [];
      userPreferences = prefs.getStringList('userPreferences') ?? [];
      
      String? mealJson = prefs.getString('mealSuggestions');
      if (mealJson != null) {
        List<dynamic> mealList = jsonDecode(mealJson);
        mealSuggestions = mealList.cast<Map<String, dynamic>>();
      }
      
      print('✅ Loaded data: ${pantryItems.length} pantry, ${mealSuggestions.length} meals');
    } catch (e) {
      print('⚠️ Load error: $e');
    }
  }

  Future<void> saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pantryItems', pantryItems);
      await prefs.setStringList('userPreferences', userPreferences);
      await prefs.setString('mealSuggestions', jsonEncode(mealSuggestions));
      print('✅ Saved data successfully');
    } catch (e) {
      print('⚠️ Save error: $e');
    }
  }

  void updateFromAI(Map<String, dynamic> actions) {
    bool hasChanges = false;
    
    if (actions['pantry_add'] != null) {
      for (String item in List<String>.from(actions['pantry_add'])) {
        if (!pantryItems.contains(item.toLowerCase())) {
          pantryItems.add(item.toLowerCase());
          hasChanges = true;
          print('🥘 Added to pantry: $item');
        }
      }
    }
    
    if (actions['pantry_remove'] != null) {
      for (String item in List<String>.from(actions['pantry_remove'])) {
        pantryItems.removeWhere((i) => 
          i.toLowerCase().contains(item.toLowerCase()) ||
          item.toLowerCase().contains(i.toLowerCase()));
        hasChanges = true;
        print('❌ Removed from pantry: $item');
      }
    }
    
    if (actions['meals_suggest'] != null) {
      for (dynamic meal in actions['meals_suggest']) {
        if (meal is String) {
          Map<String, dynamic> recipeObj = {
            'name': meal,
            'ingredients': ['Check recipe for details'],
            'prep_time': '30 minutes',
            'difficulty': 'Medium',
            'steps': ['Follow traditional cooking method'],
            'description': 'Delicious South Indian dish',
            'region': 'General',
            'serves': '4 people',
            'tips': ['Use fresh ingredients']
          };
          if (!mealSuggestions.any((m) => m['name'].toLowerCase() == meal.toLowerCase())) {
            mealSuggestions.add(recipeObj);
            hasChanges = true;
            print('🍛 Added meal: $meal');
          }
        } else if (meal is Map<String, dynamic>) {
          if (!mealSuggestions.any((m) => m['name'].toLowerCase() == meal['name'].toLowerCase())) {
            mealSuggestions.add(meal);
            hasChanges = true;
            print('🍛 Added detailed recipe: ${meal['name']}');
          }
        }
      }
      
      if (mealSuggestions.length > 20) {
        mealSuggestions.removeAt(0);
      }
    }
    
    if (actions['preferences_update'] != null) {
      for (String pref in List<String>.from(actions['preferences_update'])) {
        if (!userPreferences.contains(pref)) {
          userPreferences.add(pref);
          hasChanges = true;
          print('💭 Added preference: $pref');
        }
      }
    }
    
    if (hasChanges) {
      saveData();
    }
  }

  String getPantryString() {
    if (pantryItems.isEmpty) {
      return "Your pantry is empty. Tell me what ingredients you have!";
    }
    return "Available: ${pantryItems.join(', ')}";
  }

  String getPreferencesString() {
    if (userPreferences.isEmpty) {
      return "Tell me about your food preferences!";
    }
    return "Your preferences: ${userPreferences.join(', ')}";
  }
  
  void removePantryItem(String item) {
    pantryItems.remove(item);
    saveData();
  }
  
  void removeMealSuggestion(Map<String, dynamic> meal) {
    mealSuggestions.remove(meal);
    saveData();
  }
}

// ============ MAIN SCREEN ============
class PureAIDietBotScreen extends StatefulWidget {
  @override
  _PureAIDietBotScreenState createState() => _PureAIDietBotScreenState();
}

class _PureAIDietBotScreenState extends State<PureAIDietBotScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final PureAIDataManager _dataManager = PureAIDataManager();
  List<ChatMessage> _messages = [];
  bool _isThinking = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAppData();
  }

  Future<void> _loadAppData() async {
    await _dataManager.loadData();
    await _loadChatHistory();
    if (_messages.isEmpty) {
      _addBotMessage("Namaste! I'm Ruchi, your AI-powered South Indian cuisine expert! 🍛\n\nI understand ALL Indian languages - Telugu, Tamil, Malayalam, Kannada, Hindi, and English!\n\nJust tell me what ingredients you have or what you want to cook, and I'll give you complete recipes with cooking steps!\n\nTry saying:\n• 'నేను వంకాయ కలిగి ఉన్నాను' (Telugu)\n• 'I have rice and dal' (English)\n• 'என்னிடம் தக்காளி உள்ளது' (Tamil)");
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatJson = prefs.getString('chatHistory');
      if (chatJson != null) {
        List<dynamic> chatList = jsonDecode(chatJson);
        setState(() {
          _messages = chatList
              .map((e) => ChatMessage(text: e['text'], isUser: e['isUser']))
              .toList();
        });
      }
    } catch (e) {
      print('⚠️ Chat load error: $e');
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatList = _messages
          .map((m) => {'text': m.text, 'isUser': m.isUser}).toList();
      await prefs.setString('chatHistory', jsonEncode(chatList));
    } catch (e) {
      print('⚠️ Chat save error: $e');
    }
  }

  void _addBotMessage(String message) {
    setState(() {
      _messages.add(ChatMessage(text: message, isUser: false));
    });
    _saveChatHistory();
  }

  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty || _isThinking) return;
    
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isThinking = true;
    });
    
    _textController.clear();
    _saveChatHistory();
    _scrollToBottom();

    try {
      Map<String, dynamic> aiResult = await PureAIGroqService.getAIResponseWithActions(
        text,
        _messages.map((m) => '${m.isUser ? "User" : "Bot"}: ${m.text}').toList(),
        _dataManager.pantryItems,
        _dataManager.mealSuggestions.map((recipe) => recipe['name'] as String).toList(),
      );
      
      String aiResponse = aiResult['response'];
      Map<String, dynamic> actions = aiResult['actions'] ?? {};

      setState(() {
        _isThinking = false;
        _messages.add(ChatMessage(text: aiResponse, isUser: false));
        _dataManager.updateFromAI(actions);
      });
      
      _saveChatHistory();
      _scrollToBottom();
      
    } catch (e) {
      setState(() {
        _isThinking = false;
        _messages.add(ChatMessage(
          text: "Sorry, I'm having trouble connecting right now. Please try again! 😊",
          isUser: false,
        ));
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [
            Icon(Icons.psychology, color: Colors.white),
            SizedBox(width: 8),
            Text('AI South Indian Diet Bot')
          ]),
          backgroundColor: Colors.orange[700],
          bottom: TabBar(
            tabs: [
              Tab(icon: Icon(Icons.chat), text: 'AI Chat'),
              Tab(icon: Icon(Icons.restaurant_menu), text: 'Recipes'),
              Tab(icon: Icon(Icons.kitchen), text: 'Pantry'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildChatTab(),
            _buildRecipesTab(),
            _buildPantryTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        if (_dataManager.pantryItems.isNotEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            margin: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.psychology, size: 16, color: Colors.green[700]),
                  SizedBox(width: 4),
                  Text('AI Tracked Pantry:', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ]),
                SizedBox(height: 4),
                Text(_dataManager.getPantryString(), 
                    style: TextStyle(fontSize: 11)),
              ]
            ),
          ),
        
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(16),
            itemCount: _messages.length + (_isThinking ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _messages.length && _isThinking) {
                return Container(
                  margin: EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange,
                        child: Icon(Icons.psychology, color: Colors.white),
                      ),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("🧠 AI is thinking...", 
                                style: TextStyle(color: Colors.orange[800], fontStyle: FontStyle.italic)),
                            SizedBox(width: 8),
                            SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                              ),
                            ),
                          ]
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _messages[index];
            },
          ),
        ),
        
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 5)],
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: _isThinking ? 'AI is thinking...' : 'Type in any language...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  prefixIcon: Icon(Icons.psychology, color: Colors.orange),
                ),
                onSubmitted: _isThinking ? null : _handleSubmitted,
                enabled: !_isThinking,
                maxLines: 1,
                textInputAction: TextInputAction.send,
              ),
            ),
            SizedBox(width: 8),
            FloatingActionButton.small(
              onPressed: _isThinking ? null : () => _handleSubmitted(_textController.text),
              backgroundColor: _isThinking ? Colors.grey : Colors.orange,
              child: Icon(_isThinking ? Icons.hourglass_empty : Icons.send),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildRecipesTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.orange, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI Recipe Collection',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Complete recipes with cooking steps from AI',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          
          if (_dataManager.mealSuggestions.isEmpty) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.restaurant_menu, size: 48, color: Colors.grey[400]),
                    SizedBox(height: 12),
                    Text('No AI recipes yet!',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Chat with me about ingredients to get detailed recipes with cooking steps!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text('AI Recipe Collection (${_dataManager.mealSuggestions.length})',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            
            ..._dataManager.mealSuggestions.reversed.map((recipe) => Card(
              margin: EdgeInsets.only(bottom: 12),
              elevation: 3,
              child: InkWell(
                onTap: () => _showRecipePopup(context, recipe),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.restaurant, color: Colors.orange[700], size: 24),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  recipe['name'] ?? 'Unknown Recipe',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  recipe['description'] ?? 'Delicious dish',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          _buildInfoChip(Icons.access_time, recipe['prep_time'] ?? '30 mins', Colors.blue),
                          SizedBox(width: 8),
                          _buildInfoChip(Icons.signal_cellular_alt, recipe['difficulty'] ?? 'Medium', Colors.green),
                          SizedBox(width: 8),
                          _buildInfoChip(Icons.people, recipe['serves'] ?? '4', Colors.purple),
                          SizedBox(width: 8),
                          _buildInfoChip(Icons.location_on, recipe['region'] ?? 'General', Colors.red),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tap to see complete recipe with ingredients and cooking steps!',
                        style: TextStyle(
                          fontSize: 11, 
                          color: Colors.orange[700], 
                          fontStyle: FontStyle.italic
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )).toList(),
          ],
          
          if (_dataManager.userPreferences.isNotEmpty) ...[
            SizedBox(height: 24),
            Text('Your Preferences',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.favorite, color: Colors.blue[700], size: 16),
                    SizedBox(width: 8),
                    Text('AI Learned About You:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  SizedBox(height: 8),
                  Text(_dataManager.getPreferencesString()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color[700]),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 10, color: color[700], fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _showRecipePopup(BuildContext context, Map<String, dynamic> recipe) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange[400]!, Colors.orange[600]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.restaurant, color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              recipe['name'] ?? 'Recipe',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        recipe['description'] ?? 'Delicious South Indian dish',
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Info chips
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildInfoChip(Icons.access_time, recipe['prep_time'] ?? '30 mins', Colors.blue),
                            _buildInfoChip(Icons.signal_cellular_alt, recipe['difficulty'] ?? 'Medium', Colors.green),
                            _buildInfoChip(Icons.people, recipe['serves'] ?? '4 people', Colors.purple),
                            _buildInfoChip(Icons.location_on, recipe['region'] ?? 'General', Colors.red),
                          ],
                        ),
                        SizedBox(height: 20),
                        
                        // Ingredients
                        Text(
                          '🥘 Ingredients',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[700]),
                        ),
                        SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: (recipe['ingredients'] as List<dynamic>?)?.map((ingredient) => 
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 2),
                                child: Text('• $ingredient', style: TextStyle(fontSize: 14)),
                              )
                            ).toList() ?? [Text('• Basic ingredients as per recipe')],
                          ),
                        ),
                        SizedBox(height: 20),
                        
                        // Cooking Steps
                        Text(
                          '👩‍🍳 Cooking Steps',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[700]),
                        ),
                        SizedBox(height: 8),
                        ...(recipe['steps'] as List<dynamic>?)?.asMap().entries.map((entry) => 
                          Container(
                            margin: EdgeInsets.only(bottom: 8),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.blue[600],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${entry.key + 1}',
                                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    entry.value.toString(),
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          )
                        ).toList() ?? [Text('Follow traditional cooking method')],
                        
                        // Tips
                        if (recipe['tips'] != null && (recipe['tips'] as List).isNotEmpty) ...[
                          SizedBox(height: 20),
                          Text(
                            '💡 Pro Tips',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[700]),
                          ),
                          SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: (recipe['tips'] as List<dynamic>).map((tip) => 
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 2),
                                  child: Text('💡 $tip', style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                                )
                              ).toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Bottom actions
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _handleSubmitted("Tell me more cooking tips for ${recipe['name']}");
                          },
                          icon: Icon(Icons.psychology),
                          label: Text('Ask AI for Tips'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _dataManager.removeMealSuggestion(recipe);
                          });
                          Navigator.of(context).pop();
                        },
                        icon: Icon(Icons.delete, color: Colors.red[400]),
                        tooltip: 'Remove Recipe',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPantryTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.psychology, color: Colors.orange, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI-Managed Pantry',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Automatically tracked from our conversation!',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          
          Text('Your Ingredients (${_dataManager.pantryItems.length})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          
          if (_dataManager.pantryItems.isEmpty) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.psychology, size: 48, color: Colors.grey[400]),
                    SizedBox(height: 12),
                    Text('Tell me what you have!',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Just mention ingredients in ANY language:\n• "I have rice and dal"\n• "నేను వంకాయ కలిగి ఉన్నాను"\n• "என்னிடம் தக்காளி உள்ளது"',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dataManager.pantryItems.map((ingredient) => Card(
                color: Colors.green[50],
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.eco, size: 16, color: Colors.green[600]),
                      SizedBox(width: 6),
                      Text(ingredient, style: TextStyle(fontWeight: FontWeight.w500)),
                      SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _dataManager.removePantryItem(ingredient);
                          });
                        },
                        child: Icon(Icons.close, size: 16, color: Colors.red[400]),
                      ),
                    ],
                  ),
                ),
              )).toList(),
            ),
          ],
          
          SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lightbulb, color: Colors.orange[700], size: 16),
                  SizedBox(width: 8),
                  Text('AI Tip:', style: TextStyle(fontWeight: FontWeight.bold)),
                ]),
                SizedBox(height: 8),
                Text('I understand ingredients in ALL languages! Just chat naturally:\n• Telugu: "నా దగ్గర వంకాయ ఉంది"\n• Tamil: "என்னிடம் கத்திரிக்காய் உள்ளது"\n• English: "I have brinjal and rice"',
                    style: TextStyle(fontSize: 12, color: Colors.orange[800])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;

  const ChatMessage({Key? key, required this.text, required this.isUser}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: Colors.orange,
              child: Icon(Icons.psychology, color: Colors.white, size: 20),
            ),
            SizedBox(width: 8)
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75
              ),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[100] : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: !isUser ? Border.all(color: Colors.orange[200]!) : null,
              ),
              child: Text(text, style: TextStyle(fontSize: 14)),
            ),
          ),
          if (isUser) ...[
            SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.blue,
              child: Icon(Icons.person, color: Colors.white, size: 20),
            )
          ]
        ],
      ),
    );
  }
}

/*
🚀 FINAL SETUP:

1. Add to pubspec.yaml:
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  flutter_dotenv: ^5.1.0
  shared_preferences: ^2.2.2

flutter:
  assets:
    - .env

2. Create .env file:
GROQ_API_KEY=your_groq_key_here

3. Run:
flutter pub get
flutter run -d chrome

✅ WORKING FEATURES:
• Real Groq AI integration
• Complete recipe popups with cooking steps
• Multi-language ingredient tracking
• Persistent chat history and data
• Auto-scroll chat
• Beautiful UI

🧪 TEST:
"I have vankaya and rice, give me a recipe"
"నేను టమాట కలిగి ఉన్నాను"
*/