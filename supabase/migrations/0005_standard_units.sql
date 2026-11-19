-- Owner decision, 2026-11-19: the app offers standard units only: kg, g, quintal, tonne,
-- litre, cent, acre, hectare, are, and the counts piece, nut, bunch and sheet. The
-- traditional measure para, the only other unit in the templates, is retired rather than
-- deleted: phones that already have it learn of it at their next sync, and an entry
-- recorded in it keeps its unit. Template release 2.
update public.template_items
set is_active = false, template_version = 2, updated_at = now()
where list_type = 'unit' and code = 'para'
  and crop_id = (select id from public.crops where code = 'paddy' and owner_farm_id is null);
