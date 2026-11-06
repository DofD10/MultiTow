package multitow;

/**
 * Eine Art, Verbindungen sichtbar zu zeichnen: TextureLinkStyle (Bild zwischen den Kupplungspunkten) und
 * ModelLinkStyle (3D-Modell der Kette, ab 0.16).
 *
 * <pre>
 *            LinkStyle  (Schnittstelle)
 *             /                \
 *  TextureLinkStyle       ModelLinkStyle
 *   (heute, Bild)        (spaeter, 3D-Modell)
 * </pre>
 */
public interface LinkStyle {
    /** true, wenn alles Noetige (Bilder, Modelle) geladen ist. Sonst wird auf eine einfachere Art zurueckgefallen. */
    boolean isAvailable();

    /** Eine Verbindung zeichnen. light = Helligkeit 0..1 (Tageslicht). */
    void draw(LinkGeometry g, float light);
}
