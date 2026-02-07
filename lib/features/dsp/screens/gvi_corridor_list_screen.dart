import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class GviCorridorListScreen extends StatefulWidget {
  final String homeCountry;
  const GviCorridorListScreen({super.key, required this.homeCountry});

  @override
  State<GviCorridorListScreen> createState() => _GviCorridorListScreenState();
}

class _GviCorridorListScreenState extends State<GviCorridorListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  final Map<String, double> _countryGvis = {};
  final Map<String, bool> _countryTrendUp = {};
  Timer? _simulationTimer;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _startSimulation();
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          for (final country in countries) {
            final name = country.name;
            if (!_countryGvis.containsKey(name)) {
              _countryGvis[name] = (1.1 + (name.length % 5) * 0.1);
              _countryTrendUp[name] = true;
            }
            
            final change = (_random.nextDouble() * 0.09 + 0.01);
            final up = _random.nextBool();
            _countryTrendUp[name] = up;
            if (up) {
              _countryGvis[name] = (_countryGvis[name]! + change).clamp(1.10, 1.80);
            } else {
              _countryGvis[name] = (_countryGvis[name]! - change).clamp(1.10, 1.80);
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filter out home country and search query
    final filteredCountries = countries.where((c) {
      final matchesSearch = c.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final isNotHome = c.name != widget.homeCountry;
      return matchesSearch && isNotHome;
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('GVI Bilateral Corridors', 
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.accentDark,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.accentDark,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search bilateral countries...',
                hintStyle: TextStyle(color: Colors.white.withAlpha(153)),
                prefixIcon: const Icon(LucideIcons.search, color: Colors.white70, size: 20),
                filled: true,
                fillColor: Colors.white.withAlpha(26),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              ),
            ),
          ),
          
          Expanded(
            child: ListView.separated(
              padding: AppTheme.pagePaddingEdgeInsets.copyWith(top: 16, bottom: 32),
              itemCount: filteredCountries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final country = filteredCountries[index];
                final name = country.name;
                
                // Use simulated values
                final gviValue = _countryGvis[name] ?? (1.1 + (name.length % 5) * 0.1);
                final isUp = _countryTrendUp[name] ?? true;
                
                final statuses = ['Stable', 'Rising', 'Active', 'Growing', 'High Liquidity'];
                final status = statuses[name.length % statuses.length];
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(name, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Text(status, 
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.withAlpha(204))),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(gviValue.toStringAsFixed(2), 
                        style: TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.bold, 
                          color: isUp ? AppTheme.accent : Colors.redAccent,
                        )),
                      const Text('GVI', 
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
