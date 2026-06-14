import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    content = f.read()

# Make sure glass card background logic matches what we need
# We used GlassCard for the sort button, but let's check its styling in library_screen
# Wait, GlassCard uses borderRadius. We passed double to GlassCard? Let's check `GlassCard(borderRadius: 20`
# The codebase requires primitive double for GlassCard borderRadius. That's fine.

# Let's ensure glass_card is imported
if "import '../../../player/presentation/widgets/glass_card.dart';" not in content:
    content = "import '../../../player/presentation/widgets/glass_card.dart';\n" + content

with open('lib/features/library/presentation/screens/library_screen.dart', 'w') as f:
    f.write(content)
