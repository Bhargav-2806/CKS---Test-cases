---
name: FreshMart
colors:
  surface: '#fcf9f8'
  surface-dim: '#dcd9d9'
  surface-bright: '#fcf9f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f2'
  surface-container: '#f0eded'
  surface-container-high: '#eae7e7'
  surface-container-highest: '#e5e2e1'
  on-surface: '#1c1b1b'
  on-surface-variant: '#41493e'
  inverse-surface: '#313030'
  inverse-on-surface: '#f3f0ef'
  outline: '#717a6d'
  outline-variant: '#c0c9bb'
  surface-tint: '#2a6b2c'
  primary: '#00450d'
  on-primary: '#ffffff'
  primary-container: '#1b5e20'
  on-primary-container: '#90d689'
  inverse-primary: '#91d78a'
  secondary: '#9e4200'
  on-secondary: '#ffffff'
  secondary-container: '#fb6d00'
  on-secondary-container: '#562100'
  tertiary: '#323e36'
  on-tertiary: '#ffffff'
  tertiary-container: '#49554c'
  on-tertiary-container: '#bcc9be'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#acf4a4'
  primary-fixed-dim: '#91d78a'
  on-primary-fixed: '#002203'
  on-primary-fixed-variant: '#0c5216'
  secondary-fixed: '#ffdbcb'
  secondary-fixed-dim: '#ffb691'
  on-secondary-fixed: '#341100'
  on-secondary-fixed-variant: '#793100'
  tertiary-fixed: '#d9e6da'
  tertiary-fixed-dim: '#bdcabe'
  on-tertiary-fixed: '#131e17'
  on-tertiary-fixed-variant: '#3e4a41'
  background: '#fcf9f8'
  on-background: '#1c1b1b'
  surface-variant: '#e5e2e1'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-sm:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px
  container-max: 1280px
  gutter: 24px
  margin-desktop: 32px
  margin-mobile: 16px
---

## Brand & Style
The brand personality is rooted in reliability, vitality, and clarity. As a modern grocery and retail platform, the visual language must communicate freshness and efficiency while building a foundation of trust with the user. 

The design style follows a **Corporate / Modern** aesthetic with a focus on high-quality whitespace and clear information hierarchy. By utilizing a "Clean Retail" approach, the interface prioritizes product photography and price legibility over decorative elements. The goal is to evoke the feeling of a well-organized, premium physical supermarket where the path to purchase is frictionless and the atmosphere is welcoming.

## Colors
The palette is led by a deep, organic green to emphasize health and grocery expertise. This is balanced by a high-energy orange accent used sparingly for conversion-focused actions, promotions, and notifications.

- **Primary:** Used for brand presence, primary navigation, and "Safe" success states.
- **Secondary (Accent):** Reserved for "Add to Cart," sale badges, and critical calls to action.
- **Tertiary:** A soft tint of the primary green used for subtle backgrounds, row striping, or selected states in menus.
- **Neutral:** A near-black for maximum contrast and readability on white backgrounds.
- **Status Colors:** Use standard semantic reds for errors and ambers for warnings, ensuring they maintain the high-chroma, clean feel of the primary palette.

## Typography
This design system utilizes **Inter** exclusively to ensure a systematic, utilitarian, and highly legible experience across all touchpoints. 

The type scale is designed for rapid scanning. Headlines use tighter letter spacing and heavier weights to create a strong visual anchor for product sections. The base font size is set to 16px to ensure accessibility for a wide demographic. For pricing, use `headline-md` or `headline-sm` to ensure the cost is the most prominent element on product cards.

## Layout & Spacing
The layout employs a **Fluid Grid** system based on a 12-column desktop architecture. 

- **Desktop:** 12 columns with 24px gutters and 32px side margins. 
- **Tablet:** 8 columns with 16px gutters.
- **Mobile:** 4 columns with 16px margins.

Spacing follows an 8px rhythmic scale (with a 4px step for tight internal component spacing). Generous padding (at least 24px) should be used between major sections to prevent the interface from feeling "discount" or cluttered. Vertical rhythm should prioritize grouping related items (like product images and titles) tightly, while separating distinct categories with at least 48px of whitespace.

## Elevation & Depth
Depth is handled through **Tonal Layers** and **Ambient Shadows** to maintain a clean, flat-leaning aesthetic that still feels tactile.

- **Level 0 (Background):** Solid #FFFFFF or a very light neutral gray (#F9F9F9) for the main canvas.
- **Level 1 (Cards/Surface):** Pure white surfaces with a soft, diffused shadow (0px 4px 12px, 5% opacity black). This is the default state for product cards and search bars.
- **Level 2 (Hover/Active):** Slightly more pronounced shadow (0px 8px 24px, 8% opacity black) to indicate interactivity.
- **Level 3 (Modals/Overlays):** High-diffusion shadows with a 15% opacity backdrop blur (glassmorphism) behind them to keep the user focused on the task at hand.

## Shapes
A "Rounded" shape language is applied across the design system to soften the corporate structure and make the brand feel more approachable. 

The standard corner radius is **8px** (`rounded-md`). Larger components like promotional banners or search containers may use `rounded-lg` (16px) or `rounded-xl` (24px). Buttons and chips should never be fully pill-shaped; they must maintain the 8px radius to stay consistent with the structured, trustworthy grid of the e-commerce environment.

## Components
Consistent component behavior ensures a predictable shopping experience.

- **Buttons:** Primary buttons use a solid green background with white text. Accent/Action buttons (Add to Cart) use the bright orange background. Use a subtle brightness shift (5-10%) on hover rather than a color change.
- **Product Cards:** Must have a 1px soft gray border (#EEEEEE) and a subtle Level 1 shadow. Ensure the product image is the hero of the card.
- **Input Fields:** Use 8px rounded corners with a 1px border. Focus state should utilize a 2px primary green stroke.
- **Chips & Tags:** Used for categories or "Freshness" indicators. These should have a light green background with dark green text to signify health.
- **Checkboxes/Radios:** Utilize the primary green for selected states.
- **Lists:** Use ample vertical padding (16px) and subtle horizontal dividers to separate items in the cart or account settings.