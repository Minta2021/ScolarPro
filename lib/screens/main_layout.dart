import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/annee_scolaire.dart';
import '../theme/app_theme.dart';
import 'class_list_screen.dart';
import 'settings_screen.dart';
import 'export_screen.dart';
import 'statistics_screen.dart';
import 'comptabilite_screen.dart';
import 'cartes_scolaires_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const ClassListScreen(),
    const StatisticsScreen(),
    const ComptabiliteScreen(),
    const CartesScolairesScreen(),
    const ExportScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final etab = state.etablissement;
    final isConfigured = etab != null && etab.nom.isNotEmpty;

    return Scaffold(
      body: Row(
        children: [
          // ── Premium Sidebar ──────────────────────────────
          Container(
            width: 264,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.sidebarDark,
                  Color(0xFF0A0F1E),
                ],
              ),
            ),
            child: Column(
              children: [

                // ── Sidebar Header ─────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Logo container
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.primary.withValues(alpha: 0.3),
                              AppTheme.secondary.withValues(alpha: 0.2),
                            ],
                          ),
                          border: Border.all(
                            color: AppTheme.primaryLight.withValues(alpha: 0.3),
                            width: 1,
                          ),
                          image: isConfigured && etab.logoPath != null && etab.logoPath!.isNotEmpty
                              ? DecorationImage(
                                  image: FileImage(File(etab.logoPath!)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: !isConfigured || etab.logoPath == null || etab.logoPath!.isEmpty
                            ? const Icon(
                                Icons.school_rounded,
                                color: AppTheme.primaryLight,
                                size: 22,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isConfigured ? etab.nom : "Mon Établissement",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            if (isConfigured && state.anneesScolaires.isNotEmpty)
                              DropdownButtonHideUnderline(
                                child: SizedBox(
                                  height: 22,
                                  child: DropdownButton<AnneeScolaire>(
                                    value: state.selectedAnneeScolaire,
                                    dropdownColor: AppTheme.sidebarDark,
                                    icon: Icon(
                                      Icons.unfold_more_rounded,
                                      color: Colors.white.withValues(alpha: 0.4),
                                      size: 14,
                                    ),
                                    isExpanded: true,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11,
                                    ),
                                    onChanged: (AnneeScolaire? newYear) {
                                      if (newYear != null) {
                                        state.selectAnneeScolaire(newYear);
                                      }
                                    },
                                    items: state.anneesScolaires.map((AnneeScolaire year) {
                                      return DropdownMenuItem<AnneeScolaire>(
                                        value: year,
                                        child: Text(
                                          "${year.libelle}${year.active ? ' ● Actif' : ''}",
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: year.active ? FontWeight.w600 : FontWeight.normal,
                                            color: year.active
                                                ? AppTheme.accent
                                                : Colors.white.withValues(alpha: 0.6),
                                            fontSize: 11,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              )
                            else
                              Text(
                                "Non configuré",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Navigation Section Label ───────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "NAVIGATION",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),

                // ── Navigation Items ───────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        _buildNavItem(
                          index: 0,
                          icon: Icons.grid_view_rounded,
                          activeIcon: Icons.grid_view_rounded,
                          label: "Classes & Élèves",
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          index: 1,
                          icon: Icons.analytics_outlined,
                          activeIcon: Icons.analytics_rounded,
                          label: "Statistiques",
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          index: 2,
                          icon: Icons.account_balance_wallet_outlined,
                          activeIcon: Icons.account_balance_wallet_rounded,
                          label: "Comptabilité",
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          index: 3,
                          icon: Icons.badge_outlined,
                          activeIcon: Icons.badge_rounded,
                          label: "Cartes scolaires",
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          index: 4,
                          icon: Icons.table_chart_outlined,
                          activeIcon: Icons.table_chart_rounded,
                          label: "Exportation Excel",
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          index: 5,
                          icon: Icons.settings_outlined,
                          activeIcon: Icons.settings_rounded,
                          label: "Paramètres",
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Footer ────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConfigured ? AppTheme.success : AppTheme.error,
                          boxShadow: [
                            BoxShadow(
                              color: (isConfigured ? AppTheme.success : AppTheme.error)
                                  .withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "ScolarPro v2.0",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Main Content Area ──────────────────────────
          Expanded(
            child: Column(
              children: [
                // Configuration warning banner
                if (!isConfigured)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.warning_amber_rounded, color: AppTheme.accent, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Configuration requise",
                                style: TextStyle(
                                  color: AppTheme.textDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Veuillez configurer les paramètres de l'établissement pour générer les bulletins.",
                                style: TextStyle(
                                  color: AppTheme.textLight.withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedIndex = 5;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          child: const Text("Configurer", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),

                // Archive warning
                if (isConfigured && !state.isSelectedYearActive)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(left: 16, right: 16, top: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.archive_outlined, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Consultation des archives : Année Scolaire ${state.selectedAnneeScolaire?.libelle ?? ''} (Modifications autorisées)",
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: _screens[_selectedIndex],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = _selectedIndex == index;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white.withValues(alpha: 0.04),
        splashColor: AppTheme.primary.withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Active indicator bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: 3,
                height: isSelected ? 20 : 0,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: isSelected ? 10 : 0),
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected
                    ? AppTheme.primaryLight
                    : Colors.white.withValues(alpha: 0.5),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.65),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13.5,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
