import 'package:flutter/material.dart';

class CategoryHelper {
  static const String food = 'Food';
  static const String shopping = 'Shopping';
  static const String transport = 'Transport';
  static const String bills = 'Bills';
  static const String entertainment = 'Entertainment';
  static const String health = 'Health';
  static const String banking = 'Banking';
  static const String salary = 'Salary';
  static const String other = 'Other';

  static const List<String> allCategories = [
    food,
    shopping,
    transport,
    bills,
    entertainment,
    health,
    banking,
    salary,
    other,
  ];

  static IconData getIcon(String? category) {
    switch (category) {
      case food:
        return Icons.fastfood_rounded;
      case shopping:
        return Icons.shopping_bag_rounded;
      case transport:
        return Icons.directions_car_rounded;
      case bills:
        return Icons.receipt_long_rounded;
      case entertainment:
        return Icons.movie_rounded;
      case health:
        return Icons.medical_services_rounded;
      case banking:
        return Icons.account_balance_rounded;
      case salary:
        return Icons.attach_money_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  static Color getColor(String? category) {
    switch (category) {
      case food:
        return const Color(0xFFFFAB91); // Pastel Orange
      case shopping:
        return const Color(0xFF90CAF9); // Pastel Blue
      case transport:
        return const Color(0xFFA5D6A7); // Pastel Green
      case bills:
        return const Color(0xFFEF9A9A); // Pastel Red
      case entertainment:
        return const Color(0xFFCE93D8); // Pastel Purple
      case health:
        return const Color(0xFF80CBC4); // Pastel Teal
      case banking:
        return const Color(0xFF9FA8DA); // Pastel Indigo
      case salary:
        return const Color(0xFFC5E1A5); // Pastel Light Green
      default:
        return const Color(0xFFB0BEC5); // Blue Grey
    }
  }
}
