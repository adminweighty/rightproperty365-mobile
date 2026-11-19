import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/brand.dart';
import 'properties_repository.dart';
import 'properties_screens.dart' show TenancyDetails;

/// Activity, My Tenancy: the signed-in tenant's own tenancies, read only.
/// A tenancy is theirs when the landlord or agent recorded them with the
/// email address they confirmed; nobody else's is ever shown.
class MyTenancyView extends StatefulWidget {
  const MyTenancyView({super.key});

  @override
  State<MyTenancyView> createState() => _MyTenancyViewState();
}

class _MyTenancyViewState extends State<MyTenancyView> {
  Future<List<Tenancy>>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).properties.myTenancies();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AsyncView<List<Tenancy>>(
      future: _loading!,
      onRetry: () => setState(() {
        _loading = AppScope.of(context).properties.myTenancies();
      }),
      builder: (context, items) {
        if (items.isEmpty) {
          return const MessageView(
            icon: Icons.key_outlined,
            title: 'No tenancy yet',
            body:
                'Your tenancy shows here once your landlord or agent records '
                'you as the tenant with the email address you confirmed on '
                'RightProperty365.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            for (final t in items)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x3),
                child: BrandCard(
                  key: Key('my-tenancy-${t.id}'),
                  semanticLabel: '${t.place}. ${t.statusLabel}',
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x4),
                    child: TenancyDetails(t),
                  ),
                ),
              ),
            Text(
              'Rent payments, receipts and repairs will appear here as they '
              'are added. Ask your landlord or agent about any change.',
              style: text.bodySmall,
            ),
          ],
        );
      },
    );
  }
}
