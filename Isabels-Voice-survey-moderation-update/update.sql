BEGIN;
-- Requires earlier event, owner, and admission migrations.
DO $$ BEGIN
 IF to_regprocedure('public.voice_is_owner()') IS NULL OR to_regprocedure('public.voice_set_role(uuid,text)') IS NULL OR to_regclass('public.voice_admission_block') IS NULL THEN
  RAISE EXCEPTION 'Apply prior account management updates first';
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.voice_event_feedback(event_id uuid REFERENCES public.events(id) ON DELETE CASCADE,user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,attending boolean NOT NULL DEFAULT false,rating integer CHECK(rating BETWEEN 1 AND 5),PRIMARY KEY(event_id,user_id));
ALTER TABLE public.voice_event_feedback ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.voice_event_feedback FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS public.voice_event_survey_control(event_id uuid PRIMARY KEY REFERENCES public.events(id) ON DELETE CASCADE,opened boolean NOT NULL DEFAULT false);
ALTER TABLE public.voice_event_survey_control ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.voice_event_survey_control FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.voice_event_info(p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.events%ROWTYPE; opened boolean;
BEGIN
 IF auth.uid() IS NULL OR public.is_member() IS DISTINCT FROM true THEN RAISE EXCEPTION 'Member required'; END IF;
 SELECT * INTO e FROM public.events WHERE id=p_id AND deleted_at IS NULL AND (is_active OR public.is_admin());
 IF NOT FOUND THEN RAISE EXCEPTION 'Event unavailable'; END IF;
 SELECT coalesce((SELECT c.opened FROM public.voice_event_survey_control c WHERE c.event_id=p_id),false) INTO opened;
 RETURN jsonb_build_object('attending',coalesce((SELECT attending FROM public.voice_event_feedback WHERE event_id=p_id AND user_id=auth.uid()),false),'rating',(SELECT rating FROM public.voice_event_feedback WHERE event_id=p_id AND user_id=auth.uid()),'survey_open',opened AND e.is_active,'survey_enabled',opened,'count',CASE WHEN public.is_admin() THEN (SELECT count(*) FROM public.voice_event_feedback WHERE event_id=p_id AND attending) END,'average',CASE WHEN public.is_admin() THEN (SELECT round(avg(rating),2) FROM public.voice_event_feedback WHERE event_id=p_id) END,'responses',CASE WHEN public.is_admin() THEN (SELECT count(rating) FROM public.voice_event_feedback WHERE event_id=p_id) END);
END; $$;
CREATE OR REPLACE FUNCTION public.voice_event_survey_set(p_id uuid,p_open boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.events%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM true THEN RAISE EXCEPTION 'Admin required'; END IF;
 IF p_open IS NULL THEN RAISE EXCEPTION 'Invalid setting'; END IF;
 SELECT * INTO e FROM public.events WHERE id=p_id AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND OR (p_open AND NOT e.is_active) THEN RAISE EXCEPTION 'Publish the event first'; END IF;
 INSERT INTO public.voice_event_survey_control(event_id,opened) VALUES(p_id,p_open) ON CONFLICT(event_id) DO UPDATE SET opened=excluded.opened;
END; $$;
CREATE OR REPLACE FUNCTION public.voice_event_submit(p_id uuid,p_attend boolean,p_rating integer) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.events%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR public.is_member() IS DISTINCT FROM true THEN RAISE EXCEPTION 'Member required'; END IF;
 SELECT * INTO e FROM public.events WHERE id=p_id AND is_active AND deleted_at IS NULL FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Event unavailable'; END IF;
 IF p_rating IS NULL THEN
  IF p_attend IS NULL OR e.ends_at IS NULL OR now()>=e.ends_at THEN RAISE EXCEPTION 'Registration closed'; END IF;
  INSERT INTO public.voice_event_feedback(event_id,user_id,attending) VALUES(p_id,auth.uid(),p_attend) ON CONFLICT(event_id,user_id) DO UPDATE SET attending=excluded.attending;
 ELSE
  IF p_rating NOT BETWEEN 1 AND 5 OR NOT EXISTS(SELECT 1 FROM public.voice_event_survey_control WHERE event_id=p_id AND opened) THEN RAISE EXCEPTION 'Survey closed'; END IF;
  INSERT INTO public.voice_event_feedback(event_id,user_id,attending,rating) VALUES(p_id,auth.uid(),false,p_rating) ON CONFLICT(event_id,user_id) DO UPDATE SET rating=excluded.rating;
 END IF;
END; $$;
-- Keep public suggestion reads limited to display fields, even for admin accounts.
REVOKE SELECT ON public.suggestions FROM PUBLIC,anon,authenticated;
REVOKE SELECT(user_id) ON public.suggestions FROM PUBLIC,anon,authenticated;
GRANT SELECT(id,title,content,reason,display_name,status,official_reply,created_at,priority) ON public.suggestions TO authenticated;
CREATE TABLE IF NOT EXISTS public.voice_moderation_access_log(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, actor uuid NOT NULL, suggestion_id uuid NOT NULL, action text NOT NULL CHECK(action IN ('lookup','restrict')),reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.voice_moderation_access_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.voice_moderation_access_log FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.voice_author_lookup(p_id uuid,p_reason text,p_confirm boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE target_id uuid; target_email text; target_role text;
BEGIN
 PERFORM 1 FROM public.voice_owner WHERE singleton FOR SHARE;
 IF auth.uid() IS NULL OR public.voice_is_owner() IS DISTINCT FROM true THEN RAISE EXCEPTION 'Owner required'; END IF;
 IF p_confirm IS DISTINCT FROM true OR p_reason IS NULL OR p_reason NOT IN ('장난·스팸','욕설·비방','개인정보 노출','기타 운영규칙 위반') THEN RAISE EXCEPTION 'Moderation reason and confirmation required'; END IF;
 SELECT s.user_id INTO target_id FROM public.suggestions s WHERE s.id=p_id;
 IF target_id IS NULL THEN RAISE EXCEPTION 'Author unavailable'; END IF;
 SELECT u.email INTO target_email FROM auth.users u WHERE u.id=target_id AND u.email_confirmed_at IS NOT NULL;
 IF target_email IS NULL THEN RAISE EXCEPTION 'Verified author unavailable'; END IF;
 SELECT r.role INTO target_role FROM public.user_roles r WHERE r.user_id=target_id;
 INSERT INTO public.voice_moderation_access_log(actor,suggestion_id,action,reason) VALUES(auth.uid(),p_id,'lookup',p_reason);
 RETURN jsonb_build_object('email',target_email,'role',CASE WHEN target_id=auth.uid() THEN 'owner' ELSE coalesce(target_role,'pending') END,'can_restrict',coalesce(target_role='student',false) AND target_id<>auth.uid());
END; $$;
CREATE OR REPLACE FUNCTION public.voice_author_restrict(p_id uuid,p_reason text,p_email text,p_confirm boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE target_id uuid; target_role text;
BEGIN
 PERFORM 1 FROM public.voice_owner WHERE singleton FOR SHARE;
 IF auth.uid() IS NULL OR public.voice_is_owner() IS DISTINCT FROM true THEN RAISE EXCEPTION 'Owner required'; END IF;
 IF p_confirm IS DISTINCT FROM true OR p_reason IS NULL OR p_reason NOT IN ('장난·스팸','욕설·비방','개인정보 노출','기타 운영규칙 위반') THEN RAISE EXCEPTION 'Moderation reason and confirmation required'; END IF;
 SELECT s.user_id INTO target_id FROM public.suggestions s WHERE s.id=p_id FOR SHARE;
 IF target_id IS NULL OR target_id=auth.uid() THEN RAISE EXCEPTION 'Author unavailable or protected'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_id::text,0));
 SELECT role INTO target_role FROM public.user_roles WHERE user_id=target_id FOR UPDATE;
 IF target_role IS DISTINCT FROM 'student' OR EXISTS(SELECT 1 FROM public.voice_owner WHERE user_id=target_id) THEN RAISE EXCEPTION 'Only approved student accounts can be restricted here'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=target_id AND email=p_email AND email_confirmed_at IS NOT NULL) THEN RAISE EXCEPTION 'Author changed; verify again'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.voice_moderation_access_log WHERE actor=auth.uid() AND suggestion_id=p_id AND action='lookup' AND reason=p_reason AND created_at>=now()-interval '15 minutes') THEN RAISE EXCEPTION 'Verify author first'; END IF;
 PERFORM public.voice_set_role(target_id,'pending');
 INSERT INTO public.voice_admission_block(user_id) VALUES(target_id) ON CONFLICT DO NOTHING;
 INSERT INTO public.voice_moderation_access_log(actor,suggestion_id,action,reason) VALUES(auth.uid(),p_id,'restrict',p_reason);
END; $$;
REVOKE ALL ON FUNCTION public.voice_event_info(uuid),public.voice_event_submit(uuid,boolean,integer),public.voice_event_survey_set(uuid,boolean),public.voice_author_lookup(uuid,text,boolean),public.voice_author_restrict(uuid,text,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.voice_event_info(uuid),public.voice_event_submit(uuid,boolean,integer),public.voice_event_survey_set(uuid,boolean),public.voice_author_lookup(uuid,text,boolean),public.voice_author_restrict(uuid,text,text,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
