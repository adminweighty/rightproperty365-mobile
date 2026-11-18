import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format.dart';
import '../../../core/location.dart';
import '../data/listing.dart';

/// The radius drawn for an approximate location: the API rounds its
/// coordinates to 2 decimals, about 1 km.
const approximateRadiusMetres = 1000.0;

/// Harare, where the map opens when there is nothing to show yet.
const defaultMapCentre = LatLng(-17.8292, 31.0522);

LatLng pointOf(ListingLocation location) =>
    LatLng(location.latitude, location.longitude);

/// A map of listings. An exact location is a pin; an approximate one is a
/// shaded area with a small button in its middle, never a pin. Every pin and
/// area is a button named after its listing, and the attribution the tile
/// provider requires is always shown.
class ListingsMap extends StatelessWidget {
  const ListingsMap({
    super.key,
    required this.tiles,
    required this.listings,
    required this.onSelect,
    this.controller,
    this.onMoved,
    this.interactive = true,
    this.initialZoom = 12,
  });

  final MapTiles tiles;
  final List<Listing> listings;
  final void Function(Listing listing) onSelect;
  final MapController? controller;

  /// Called after the person moved or zoomed the map.
  final void Function(LatLngBounds visible)? onMoved;

  /// False for the small map on a listing page until it is tapped, so it
  /// never traps scrolling.
  final bool interactive;
  final double initialZoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placed = [
      for (final l in listings)
        if (l.position != null) l,
    ];
    final points = [for (final l in placed) pointOf(l.position!)];
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: points.isEmpty ? defaultMapCentre : points.first,
        initialZoom: points.isEmpty ? 6 : initialZoom,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(48),
                maxZoom: 15,
              )
            : null,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
        onPositionChanged: onMoved == null
            ? null
            : (camera, hasGesture) {
                if (hasGesture) onMoved!(camera.visibleBounds);
              },
      ),
      children: [
        TileLayer(
          urlTemplate: tiles.urlTemplate,
          userAgentPackageName: 'com.rightproperty365.rightproperty365',
          tileProvider: tiles.tileProvider,
        ),
        CircleLayer(
          circles: [
            for (final l in placed)
              if (l.position!.approximate)
                CircleMarker(
                  point: pointOf(l.position!),
                  radius: approximateRadiusMetres,
                  useRadiusInMeter: true,
                  color: c.primary.withValues(alpha: 0.18),
                  borderColor: c.primary,
                  borderStrokeWidth: 2,
                ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final l in placed)
              Marker(
                point: pointOf(l.position!),
                width: 48,
                height: 48,
                alignment: l.position!.approximate
                    ? Alignment.center
                    : Alignment.topCenter,
                child: _MapButton(listing: l, onTap: () => onSelect(l)),
              ),
          ],
        ),
        _Attribution(tiles.attribution),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final approximate = listing.position!.approximate;
    final price =
        '${formatMoney(listing.price)}${listing.pricePerMonth ? ' per month' : ''}';
    return Semantics(
      button: true,
      label: approximate
          ? 'Approximate area of ${listing.title}, $price'
          : '${listing.title}, $price',
      excludeSemantics: true,
      child: InkResponse(
        key: Key('map-${listing.slug}'),
        onTap: onTap,
        radius: 24,
        child: approximate
            ? Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.surface,
                    border: Border.all(color: c.primary, width: 3),
                  ),
                ),
              )
            : Icon(Icons.location_on, size: 44, color: c.primary),
      ),
    );
  }
}

/// The attribution the tile provider requires, always visible. It wraps
/// rather than overflowing on a narrow map or with large text.
class _Attribution extends StatelessWidget {
  const _Attribution(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: c.surface.withValues(alpha: 0.85),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.ink),
        ),
      ),
    );
  }
}
