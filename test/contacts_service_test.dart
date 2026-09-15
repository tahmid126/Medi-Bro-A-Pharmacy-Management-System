import 'package:flutter_test/flutter_test.dart';
import 'package:medibro_update/data/services/contacts_service.dart';

void main() {
  group('Contacts Grouping and Model Tests', () {
    test('CompanyGroupResult instantiation and property access', () {
      final unique = [
        {'company_name': 'Beximco Pharma', 'id': 'c-1', 'is_local': true},
        {'company_name': 'Square Pharmaceuticals', 'id': 'c-2', 'is_local': true},
      ];
      final contacts = {
        'Beximco Pharma': [
          {'id': 's-1', 'name': 'Mr. Rahim', 'company_name': 'Beximco Pharma'},
        ],
        'Square Pharmaceuticals': [
          {'id': 's-2', 'name': 'Mr. Karim', 'company_name': 'Square Pharmaceuticals'},
        ],
      };

      final result = CompanyGroupResult(
        uniqueCompanies: unique,
        companyContacts: contacts,
      );

      expect(result.uniqueCompanies.length, 2);
      expect(result.companyContacts['Beximco Pharma']?.first['name'], 'Mr. Rahim');
      expect(result.companyContacts['Square Pharmaceuticals']?.first['name'], 'Mr. Karim');
    });
  });
}
