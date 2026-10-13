"""Makes Resources/AppIcon.icon, the app icon in Icon Composer's format: a
stone fill with a tau cut into it, like a mason's mark. The tau follows the
one in the arms of Monforte de Lemos.

    python3 scripts/make-icon.py

Open the result in Icon Composer to preview it; package-app.sh compiles it.
"""
import json, os

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "AppIcon.icon")
os.makedirs(os.path.join(out, "Assets"), exist_ok=True)

# The tau in the shield's coordinates, scaled to the icon:
# the crossbar's top dips, the arms widen to straight-cut ends, the stem
# widens toward a curved foot.
def tau(dx=0.0, dy=0.0, s=2.3, cx=480, cy=822):
    def p(x, y):
        return f"{512 + (x - cx) * s + dx:.1f},{512 + (y - cy) * s + dy:.1f}"
    return " ".join([
        f"M{p(358, 698)}",
        f"Q{p(480, 734)} {p(602, 698)}",   # top edge, dipping in the middle
        f"L{p(602, 772)}",                 # right arm's straight end
        f"Q{p(530, 752)} {p(504, 752)}",   # under the right arm, into the stem
        f"Q{p(508, 860)} {p(530, 946)}",   # right side of the stem, widening
        f"Q{p(481, 926)} {p(432, 946)}",   # the foot, curving up
        f"Q{p(454, 860)} {p(458, 752)}",   # left side of the stem
        f"Q{p(430, 752)} {p(358, 772)}",   # under the left arm
        "Z",
    ])

cut = tau()
# The carving, lit from the top left: a light lip where the stone's edge
# catches the light below and right of the cut, a dark wall inside the top
# and left edges, and the floor of the cut a little lighter.
carving = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs><clipPath id="cut"><path d="{cut}"/></clipPath></defs>
<path d="{tau(5, 7)}" fill="#F4F0E9" fill-opacity="0.85"/>
<path d="{cut}" fill="#3F3932"/>
<g clip-path="url(#cut)"><path d="{tau(14, 18)}" fill="#7B7266"/><path d="{tau(22, 28)}" fill="#8A8174"/></g>
</svg>
'''
with open(os.path.join(out, "Assets", "tau.svg"), "w") as f:
    f.write(carving)

icon = {
    "fill": {"automatic-gradient": "srgb:0.79608,0.76078,0.70588,1.00000"},
    "groups": [{
        "layers": [{"image-name": "tau.svg", "name": "tau", "glass": False}],
        "shadow": {"kind": "none", "opacity": 0},
        "translucency": {"enabled": False, "value": 0},
        "specular": False,
    }],
    "supported-platforms": {"squares": "shared"},
}
with open(os.path.join(out, "icon.json"), "w") as f:
    json.dump(icon, f, indent=2)
print("Wrote", os.path.normpath(out))
