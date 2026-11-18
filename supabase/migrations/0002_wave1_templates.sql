-- Wave 1 crop templates (task B1): coconut, rubber, pepper, banana, paddy, cardamom.
--
-- Malayalam wording, default rates and split weights need native-speaker and field review:
-- every item seeded here carries data.ml_review = true until the admin console clears it.
--
-- Ids are derived from the codes, so every environment and the phone's tests get the same ids.
-- Units: data.dimension is mass (base kg), area (base cent), volume (base litre) or count
-- (base piece); data.factor is how many base units one unit holds. A null factor means the
-- farmer sets the ratio (local measures that vary by place).

insert into public.crops (id, code, name_ml, name_en, kind, default_unit) values
  (md5('thottam:crop:coconut')::uuid, 'coconut', 'തെങ്ങ്', 'Coconut', 'perennial', 'nut'),
  (md5('thottam:crop:rubber')::uuid, 'rubber', 'റബ്ബർ', 'Rubber', 'perennial', 'kg'),
  (md5('thottam:crop:pepper')::uuid, 'pepper', 'കുരുമുളക്', 'Pepper', 'perennial', 'kg'),
  (md5('thottam:crop:banana')::uuid, 'banana', 'വാഴ', 'Banana', 'annual', 'kg'),
  (md5('thottam:crop:paddy')::uuid, 'paddy', 'നെല്ല്', 'Paddy', 'seasonal', 'kg'),
  (md5('thottam:crop:cardamom')::uuid, 'cardamom', 'ഏലം', 'Cardamom', 'perennial', 'kg')
on conflict do nothing;

insert into public.template_items (id, crop_id, list_type, code, name_ml, name_en, sort_order, data)
select
  md5('thottam:item:' || coalesce(v.crop, '*') || ':' || v.list_type || ':' || v.code)::uuid,
  c.id, v.list_type, v.code, v.name_ml, v.name_en, v.sort_order,
  v.data::jsonb || '{"ml_review": true}'
from (values
  -- units, for every crop
  (null, 'unit', 'kg', 'കിലോ', 'kg', 10, '{"dimension": "mass", "factor": 1}'),
  (null, 'unit', 'g', 'ഗ്രാം', 'gram', 20, '{"dimension": "mass", "factor": 0.001}'),
  (null, 'unit', 'quintal', 'ക്വിന്റൽ', 'quintal', 30, '{"dimension": "mass", "factor": 100}'),
  (null, 'unit', 'tonne', 'ടൺ', 'tonne', 40, '{"dimension": "mass", "factor": 1000}'),
  (null, 'unit', 'litre', 'ലിറ്റർ', 'litre', 50, '{"dimension": "volume", "factor": 1}'),
  (null, 'unit', 'piece', 'എണ്ണം', 'piece', 60, '{"dimension": "count", "factor": 1}'),
  (null, 'unit', 'cent', 'സെന്റ്', 'cent', 70, '{"dimension": "area", "factor": 1}'),
  (null, 'unit', 'acre', 'ഏക്കർ', 'acre', 80, '{"dimension": "area", "factor": 100}'),
  (null, 'unit', 'hectare', 'ഹെക്ടർ', 'hectare', 90, '{"dimension": "area", "factor": 247.105}'),
  (null, 'unit', 'are', 'ആർ', 'are', 100, '{"dimension": "area", "factor": 2.47105}'),
  ('coconut', 'unit', 'nut', 'തേങ്ങ (എണ്ണം)', 'nut', 110, '{"dimension": "count", "factor": 1}'),
  ('banana', 'unit', 'bunch', 'കുല', 'bunch', 110, '{"dimension": "count", "factor": 1}'),
  ('rubber', 'unit', 'sheet', 'ഷീറ്റ്', 'sheet', 110, '{"dimension": "count", "factor": 1}'),
  ('paddy', 'unit', 'para', 'പറ', 'para', 110, '{"dimension": "mass", "factor": null}'),

  -- expense categories, for every crop
  (null, 'expense_category', 'fertiliser', 'വളം', 'Fertiliser', 10, '{}'),
  (null, 'expense_category', 'wages', 'കൂലി', 'Wages', 20, '{}'),
  (null, 'expense_category', 'seeds', 'വിത്ത്, തൈ', 'Seeds and seedlings', 30, '{}'),
  (null, 'expense_category', 'machinery', 'യന്ത്രം', 'Machinery', 40, '{}'),
  (null, 'expense_category', 'transport', 'ഗതാഗതം', 'Transport', 50, '{}'),
  (null, 'expense_category', 'plant_protection', 'കീടനാശിനി, കുമിൾനാശിനി', 'Plant protection', 60, '{}'),
  (null, 'expense_category', 'irrigation', 'ജലസേചനം', 'Irrigation', 70, '{}'),
  (null, 'expense_category', 'electricity', 'വൈദ്യുതി', 'Electricity', 80, '{}'),
  (null, 'expense_category', 'lease', 'പാട്ടം', 'Lease rent', 90, '{}'),
  (null, 'expense_category', 'repairs', 'അറ്റകുറ്റപ്പണി', 'Repairs', 100, '{}'),
  (null, 'expense_category', 'other', 'മറ്റുള്ളവ', 'Other', 900, '{}'),

  -- rate classes for groups, with a default rate per head per day
  (null, 'rate_class', 'general', 'സാധാരണ പണി', 'General work', 10, '{"default_rate_paise": 80000}'),
  (null, 'rate_class', 'climber', 'കയറ്റക്കാർ', 'Climbers', 20, '{"default_rate_paise": 120000}'),

  -- labour tasks
  (null, 'labour_task', 'general_work', 'പൊതുപണി', 'General work', 10, '{"rate_class": "general"}'),
  (null, 'labour_task', 'weeding', 'കള പറിക്കൽ', 'Weeding', 20, '{"rate_class": "general"}'),
  (null, 'labour_task', 'manuring', 'വളമിടൽ', 'Manuring', 30, '{"rate_class": "general"}'),
  (null, 'labour_task', 'spraying', 'മരുന്ന് തളിക്കൽ', 'Spraying', 40, '{"rate_class": "general"}'),
  (null, 'labour_task', 'irrigation', 'നനയ്ക്കൽ', 'Irrigation', 50, '{"rate_class": "general"}'),
  (null, 'labour_task', 'harvest', 'വിളവെടുപ്പ്', 'Harvest', 60, '{"rate_class": "general"}'),
  ('coconut', 'labour_task', 'palm_climbing', 'തെങ്ങ് കയറ്റം', 'Palm climbing', 70, '{"rate_class": "climber"}'),
  ('coconut', 'labour_task', 'basin_opening', 'തടം തുറക്കൽ', 'Opening basins', 80, '{"rate_class": "general"}'),
  ('rubber', 'labour_task', 'tapping', 'ടാപ്പിംഗ്', 'Tapping', 70, '{"rate_class": "general"}'),
  ('rubber', 'labour_task', 'sheet_rolling', 'ഷീറ്റ് അടിക്കൽ', 'Sheet rolling', 80, '{"rate_class": "general"}'),
  ('pepper', 'labour_task', 'pepper_picking', 'കുരുമുളക് പറിക്കൽ', 'Pepper picking', 70, '{"rate_class": "climber"}'),
  ('pepper', 'labour_task', 'tying_vines', 'വള്ളി കെട്ടൽ', 'Tying vines', 80, '{"rate_class": "general"}'),
  ('banana', 'labour_task', 'propping', 'താങ്ങുകൊടുക്കൽ', 'Propping', 70, '{"rate_class": "general"}'),
  ('banana', 'labour_task', 'desuckering', 'കന്ന് നീക്കൽ', 'Removing suckers', 80, '{"rate_class": "general"}'),
  ('paddy', 'labour_task', 'transplanting', 'ഞാറുനടീൽ', 'Transplanting', 70, '{"rate_class": "general"}'),
  ('paddy', 'labour_task', 'reaping', 'കൊയ്ത്ത്', 'Reaping', 80, '{"rate_class": "general"}'),
  ('paddy', 'labour_task', 'threshing', 'മെതി', 'Threshing', 90, '{"rate_class": "general"}'),
  ('cardamom', 'labour_task', 'cardamom_picking', 'ഏലക്ക പറിക്കൽ', 'Cardamom picking', 70, '{"rate_class": "general"}'),
  ('cardamom', 'labour_task', 'trashing', 'ചവറ് നീക്കൽ', 'Trashing', 80, '{"rate_class": "general"}'),

  -- activities (crop calendar)
  ('pepper', 'activity', 'tying_vines', 'വള്ളി കെട്ടൽ', 'Tying vines', 10, '{}'),
  ('pepper', 'activity', 'shade_regulation', 'തണൽ ക്രമീകരണം', 'Shade regulation', 20, '{}'),
  ('pepper', 'activity', 'mulching', 'പുതയിടൽ', 'Mulching', 30, '{}'),
  ('pepper', 'activity', 'bordeaux_spray', 'ബോർഡോ തളിക്കൽ', 'Bordeaux spray', 40, '{}'),
  ('pepper', 'activity', 'harvest', 'വിളവെടുപ്പ്', 'Harvest', 50, '{}'),
  ('pepper', 'activity', 'drying', 'ഉണക്കൽ', 'Drying', 60, '{}'),
  ('coconut', 'activity', 'basin_opening', 'തടം തുറക്കൽ', 'Opening basins', 10, '{}'),
  ('coconut', 'activity', 'fertilising', 'വളമിടൽ', 'Fertilising', 20, '{}'),
  ('coconut', 'activity', 'irrigation', 'നനയ്ക്കൽ', 'Irrigation', 30, '{}'),
  ('coconut', 'activity', 'palm_climbing', 'തെങ്ങ് കയറ്റം', 'Palm climbing', 40, '{}'),
  ('coconut', 'activity', 'copra_drying', 'കൊപ്ര ഉണക്കൽ', 'Copra drying', 50, '{}'),
  ('rubber', 'activity', 'tapping', 'ടാപ്പിംഗ്', 'Tapping', 10, '{}'),
  ('rubber', 'activity', 'sheet_rolling', 'ഷീറ്റ് അടിക്കൽ', 'Sheet rolling', 20, '{}'),
  ('rubber', 'activity', 'smoking', 'പുകയ്ക്കൽ', 'Smoking', 30, '{}'),
  ('rubber', 'activity', 'rain_guarding', 'റെയിൻ ഗാർഡ്', 'Rain guarding', 40, '{}'),
  ('rubber', 'activity', 'weeding', 'കള വെട്ടൽ', 'Weeding', 50, '{}'),
  ('banana', 'activity', 'planting', 'നടീൽ', 'Planting', 10, '{}'),
  ('banana', 'activity', 'fertilising', 'വളമിടൽ', 'Fertilising', 20, '{}'),
  ('banana', 'activity', 'irrigation', 'നനയ്ക്കൽ', 'Irrigation', 30, '{}'),
  ('banana', 'activity', 'propping', 'താങ്ങുകൊടുക്കൽ', 'Propping', 40, '{}'),
  ('banana', 'activity', 'desuckering', 'കന്ന് നീക്കൽ', 'Removing suckers', 50, '{}'),
  ('banana', 'activity', 'harvest', 'വിളവെടുപ്പ്', 'Harvest', 60, '{}'),
  ('paddy', 'activity', 'land_preparation', 'നിലമൊരുക്കൽ', 'Land preparation', 10, '{}'),
  ('paddy', 'activity', 'sowing', 'വിതയ്ക്കൽ', 'Sowing', 20, '{}'),
  ('paddy', 'activity', 'transplanting', 'ഞാറുനടീൽ', 'Transplanting', 30, '{}'),
  ('paddy', 'activity', 'weeding', 'കള പറിക്കൽ', 'Weeding', 40, '{}'),
  ('paddy', 'activity', 'fertilising', 'വളമിടൽ', 'Fertilising', 50, '{}'),
  ('paddy', 'activity', 'reaping', 'കൊയ്ത്ത്', 'Reaping', 60, '{}'),
  ('cardamom', 'activity', 'shade_regulation', 'തണൽ ക്രമീകരണം', 'Shade regulation', 10, '{}'),
  ('cardamom', 'activity', 'trashing', 'ചവറ് നീക്കൽ', 'Trashing', 20, '{}'),
  ('cardamom', 'activity', 'fertilising', 'വളമിടൽ', 'Fertilising', 30, '{}'),
  ('cardamom', 'activity', 'spraying', 'മരുന്ന് തളിക്കൽ', 'Spraying', 40, '{}'),
  ('cardamom', 'activity', 'picking', 'വിളവെടുപ്പ്', 'Picking', 50, '{}'),
  ('cardamom', 'activity', 'curing', 'ഉണക്കൽ', 'Curing', 60, '{}'),

  -- inputs
  ('pepper', 'input', 'neem_cake', 'വേപ്പിൻപിണ്ണാക്ക്', 'Neem cake', 10, '{}'),
  ('pepper', 'input', 'bordeaux_mixture', 'ബോർഡോ മിശ്രിതം', 'Bordeaux mixture', 20, '{}'),
  ('pepper', 'input', 'trichoderma', 'ട്രൈക്കോഡെർമ', 'Trichoderma', 30, '{}'),
  ('coconut', 'input', 'organic_manure', 'ജൈവവളം', 'Organic manure', 10, '{}'),
  ('coconut', 'input', 'potash', 'പൊട്ടാഷ്', 'Potash', 20, '{}'),
  ('coconut', 'input', 'lime', 'കുമ്മായം', 'Lime', 30, '{}'),
  ('rubber', 'input', 'rubber_mixture', 'റബ്ബർ മിശ്രിത വളം', 'Rubber mixture fertiliser', 10, '{}'),
  ('rubber', 'input', 'formic_acid', 'ഫോർമിക് ആസിഡ്', 'Formic acid', 20, '{}'),
  ('rubber', 'input', 'rain_guard', 'റെയിൻ ഗാർഡ്', 'Rain guard', 30, '{}'),

  -- harvest grades
  ('pepper', 'grade', 'garbled', 'ഗാർബിൾഡ്', 'Garbled', 10, '{}'),
  ('pepper', 'grade', 'ungarbled', 'അൺഗാർബിൾഡ്', 'Ungarbled', 20, '{}'),
  ('pepper', 'grade', 'green', 'പച്ച', 'Green', 30, '{}'),
  ('coconut', 'grade', 'whole_nut', 'തേങ്ങ', 'Whole nut', 10, '{}'),
  ('coconut', 'grade', 'copra', 'കൊപ്ര', 'Copra', 20, '{}'),
  ('coconut', 'grade', 'tender_coconut', 'ഇളനീർ', 'Tender coconut', 30, '{}'),
  ('rubber', 'grade', 'rss4', 'RSS-4', 'RSS-4', 10, '{}'),
  ('rubber', 'grade', 'rss5', 'RSS-5', 'RSS-5', 20, '{}'),
  ('rubber', 'grade', 'latex', 'ലാറ്റെക്സ്', 'Latex', 30, '{}'),
  ('rubber', 'grade', 'scrap', 'ഒട്ടുപാൽ', 'Scrap', 40, '{}'),
  ('banana', 'grade', 'grade_a', 'എ ഗ്രേഡ്', 'Grade A', 10, '{}'),
  ('banana', 'grade', 'grade_b', 'ബി ഗ്രേഡ്', 'Grade B', 20, '{}'),
  ('paddy', 'grade', 'raw', 'പച്ചനെല്ല്', 'Raw paddy', 10, '{}'),
  ('paddy', 'grade', 'dried', 'ഉണക്കനെല്ല്', 'Dried paddy', 20, '{}'),
  ('cardamom', 'grade', 'size_8mm', '8 മി.മീ.ക്ക് മുകളിൽ', '8 mm and above', 10, '{}'),
  ('cardamom', 'grade', 'size_7mm', '7–8 മി.മീ.', '7 to 8 mm', 20, '{}'),
  ('cardamom', 'grade', 'size_6mm', '6–7 മി.മീ.', '6 to 7 mm', 30, '{}'),
  ('cardamom', 'grade', 'below_6mm', '6 മി.മീ.ക്ക് താഴെ', 'Below 6 mm', 40, '{}'),

  -- settings read by the override resolver
  (null, 'setting', 'overtime_rate_paise', 'ഓവർടൈം നിരക്ക് (മണിക്കൂറിന്)', 'Overtime rate per hour', 10, '{"value": 15000}'),
  (null, 'setting', 'labour_split', 'കൂലി വീതിക്കൽ', 'Labour cost split', 20, '{"value": "like_expense"}'),
  ('coconut', 'setting', 'split_weight', 'ചെലവ് വിഹിതം', 'Default cost share', 30, '{"value": 60}'),
  ('rubber', 'setting', 'split_weight', 'ചെലവ് വിഹിതം', 'Default cost share', 30, '{"value": 60}'),
  ('pepper', 'setting', 'split_weight', 'ചെലവ് വിഹിതം', 'Default cost share', 30, '{"value": 30}'),
  ('banana', 'setting', 'split_weight', 'ചെലവ് വിഹിതം', 'Default cost share', 30, '{"value": 10}'),
  ('paddy', 'setting', 'split_weight', 'ചെലവ് വിഹിതം', 'Default cost share', 30, '{"value": 60}'),
  ('cardamom', 'setting', 'split_weight', 'ചെലവ് വിഹിതം', 'Default cost share', 30, '{"value": 60}')
) as v (crop, list_type, code, name_ml, name_en, sort_order, data)
left join public.crops c on c.code = v.crop and c.owner_farm_id is null
on conflict do nothing;
