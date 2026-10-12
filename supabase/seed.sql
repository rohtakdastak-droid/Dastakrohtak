-- Dastak: dev seed data. Run after a user signs up and is promoted to admin.

-- Promote a specific user to admin (replace email).
-- update profiles set role = 'admin' where id = (
--   select id from auth.users where email = 'you@example.com'
-- );

insert into vendors (name, slug, category, description, dispatch_address, latitude, longitude,
                     min_order_paise, prep_time_minutes, sort_priority, service_radius_km, is_featured)
values
  ('Spice Route', 'spice-route', 'food',
   'Modern North-Indian plates and biryanis.',
   'Shop 12, MG Road, Jaipur', 26.9124, 75.7873,
   15000, 25, 10, 7.0, true),
  ('Green Bowl', 'green-bowl', 'food',
   'Pure-veg wraps, salads and south-Indian specials.',
   'B-14, Vaishali Nagar, Jaipur', 26.9050, 75.7420,
   10000, 20, 20, 6.0, true),
  ('Chai Point', 'chai-point', 'food',
   'Cutting chai, bun-maska and quick bites.',
   'C-3, Raja Park, Jaipur', 26.9020, 75.8300,
   5000, 10, 30, 8.0, false),
  ('The Burger Co.', 'burger-co', 'food',
   'Hand-smashed patties, loaded fries and shakes.',
   'Plot 9, Malviya Nagar, Jaipur', 26.8520, 75.8140,
   15000, 20, 40, 7.0, false)
on conflict do nothing;

-- Sample products for Spice Route
with v as (select id from vendors where slug = 'spice-route')
insert into products (vendor_id, name, description, price_paise, image_path, diet, is_available)
select v.id, x.name, x.description, x.price, null, x.diet::diet_tag, true
from v, (values
  ('Chicken Biryani', 'Dum-cooked long-grain rice with tender chicken.', 29900, 'non_veg'),
  ('Paneer Butter Masala', 'Classic rich tomato gravy with cottage cheese.', 24900, 'veg'),
  ('Dal Makhani', 'Slow-cooked black lentils with butter and cream.', 19900, 'veg'),
  ('Butter Naan', 'Fluffy tandoor naan brushed with butter.', 4900, 'veg')
) as x(name, description, price, diet);

-- Sample products for Green Bowl (pure veg)
with v as (select id from vendors where slug = 'green-bowl')
insert into products (vendor_id, name, description, price_paise, image_path, diet, is_available)
select v.id, x.name, x.description, x.price, null, 'veg'::diet_tag, true
from v, (values
  ('Veg Mezze Bowl', 'Hummus, falafel, tabbouleh and pita.', 25900),
  ('Masala Dosa', 'Crispy dosa with potato masala and chutneys.', 14900),
  ('Fresh Fruit Bowl', 'Seasonal fruits with mint and lime.', 9900)
) as x(name, description, price);

-- Default payment settings (admin should overwrite)
update payment_settings
  set upi_vpa = 'dastak@upi',
      payee_name = 'Dastak',
      instructions = 'Please pay the exact amount and submit the UPI reference ID.'
  where id = true;
