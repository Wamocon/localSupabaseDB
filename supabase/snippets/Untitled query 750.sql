-- Admin-User einrichten: nikolaj.schefner@wamocon.com
INSERT INTO public.user_profiles (id, full_name, is_admin)
VALUES ('76b60d81-4443-4995-9b5b-7d31fdf0a67c', 'Nikolaj Schefner', true)
ON CONFLICT (id) DO UPDATE SET
  is_admin  = true,
  full_name = COALESCE(EXCLUDED.full_name, public.user_profiles.full_name);

INSERT INTO public.subscriptions (user_id, plan, status, current_period_end)
VALUES ('76b60d81-4443-4995-9b5b-7d31fdf0a67c', 'pro', 'active', now() + INTERVAL '10 years')
ON CONFLICT (user_id) DO UPDATE SET
  plan               = 'pro',
  status             = 'active',
  current_period_end = now() + INTERVAL '10 years';

SELECT up.id, up.full_name, up.is_admin, s.plan, s.status
FROM public.user_profiles up
JOIN public.subscriptions s ON s.user_id = up.id
WHERE up.id = '76b60d81-4443-4995-9b5b-7d31fdf0a67c';