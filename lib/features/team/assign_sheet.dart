import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../workspace/workspace.dart';
import 'team_repository.dart';

/// Who can be given a request: the members who hold leads, per organisation.
typedef _Candidates =
    List<({WorkOrganisation organisation, TeamMember member})>;

/// Lets an Agency Principal or administrator give a received request to a
/// team member, or return it to the agency inbox. Returns what was done, or
/// null when nothing changed.
Future<String?> showAssignSheet(
  BuildContext context, {
  required String requestId,
  required List<WorkOrganisation> organisations,
  String? current,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _AssignSheet(
    requestId: requestId,
    organisations: organisations,
    current: current,
    repository: AppScope.of(context).team,
  ),
);

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({
    required this.requestId,
    required this.organisations,
    required this.current,
    required this.repository,
  });

  final String requestId;
  final List<WorkOrganisation> organisations;
  final String? current;
  final TeamRepository repository;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  late final Future<_Candidates> _candidates = _load();
  final _query = TextEditingController();
  bool _saving = false;
  String? _problem;

  Future<_Candidates> _load() async {
    final teams = await Future.wait([
      for (final organisation in widget.organisations)
        widget.repository.members(organisation.id),
    ]);
    return [
      for (var i = 0; i < teams.length; i++)
        for (final member in teams[i].members)
          if (member.canHoldLeads)
            (organisation: widget.organisations[i], member: member),
    ];
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _give(TeamMember? member) async {
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await widget.repository.assign(widget.requestId, member?.userId);
      if (!mounted) return;
      Navigator.pop(
        context,
        member == null
            ? 'Returned to the agency inbox'
            : 'Assigned to ${member.name}',
      );
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = failure.code == 'VALIDATION_FAILED'
              ? 'That person cannot be given enquiries. Choose another member.'
              : teamMessage(failure);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final grouped = widget.organisations.length > 1;
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Assign this enquiry', style: text.titleLarge),
                const SizedBox(height: Space.x1),
                Text(
                  'The member is emailed. Other agents stop seeing it until it '
                  'goes back to the agency inbox.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: Space.x3),
                TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search the team',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                if (_problem != null) ...[
                  const SizedBox(height: Space.x2),
                  Text(
                    _problem!,
                    style: text.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_saving) const LinearProgressIndicator(),
          Expanded(
            child: FutureBuilder<_Candidates>(
              future: _candidates,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(Space.x4),
                    child: Text(
                      'We could not load the team. Check your connection and try again.',
                      style: text.bodyLarge,
                    ),
                  );
                }
                final words = _query.text.trim().toLowerCase();
                final shown = [
                  for (final c in snapshot.data!)
                    if (words.isEmpty ||
                        c.member.name.toLowerCase().contains(words) ||
                        c.member.roleLabel.toLowerCase().contains(words))
                      c,
                ];
                return ListView(
                  children: [
                    if (widget.current != null)
                      ListTile(
                        key: const Key('assign-inbox'),
                        enabled: !_saving,
                        leading: const Icon(Icons.inbox_outlined),
                        title: const Text('Back to the agency inbox'),
                        subtitle: Text('Now with ${widget.current}'),
                        onTap: () => _give(null),
                      ),
                    if (shown.isEmpty)
                      const ListTile(title: Text('No matches')),
                    for (final c in shown)
                      ListTile(
                        key: Key('assign-to-${c.member.userId}'),
                        enabled: !_saving && c.member.name != widget.current,
                        title: Text(
                          c.member.isYou
                              ? '${c.member.name} (you)'
                              : c.member.name,
                        ),
                        subtitle: Text(
                          [
                            c.member.roleLabel,
                            '${c.member.openLeads} open',
                            if (grouped) c.organisation.name,
                          ].join(' · '),
                        ),
                        trailing: c.member.name == widget.current
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => _give(c.member),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
