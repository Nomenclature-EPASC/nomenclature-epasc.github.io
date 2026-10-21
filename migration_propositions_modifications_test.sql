-- Nomenclature EPASC — migration préparatoire pour le projet Supabase de test
-- Référence attendue : dllbwtpooiskvuhtxpck
--
-- IMPORTANT
-- 1. Ce fichier n'a pas été exécuté.
-- 2. L'UUID ci-dessous a été fourni comme vérifié dans Auth > Users du projet
--    de TEST. Ne le remplacez qu'après une nouvelle vérification de ce compte.
-- 3. Exécutez le script complet dans le SQL Editor du projet de test uniquement.
-- 4. Les changements sont transactionnels. Une erreur interrompt le bloc ;
--    COMMIT sur une transaction PostgreSQL en échec la termine par un rollback.
--
-- La politique d'écriture sur public.numeros est limitée à la liste admin.
-- Les privilèges SQL authenticated existants sont conservés ; RLS les borne.

BEGIN;

-- Configuration unique : UUID vérifié du premier administrateur autorisé.
CREATE TEMP TABLE _epasc_migration_admin_config
    (admin_user_id uuid) ON COMMIT DROP;
INSERT INTO _epasc_migration_admin_config (admin_user_id)
VALUES ('7dab4a65-e2ff-4aef-bf85-a7ced32c8497'::uuid);

DO $preflight$
DECLARE
    v_admin uuid;
    v_id_type oid;
    v_pk_ok boolean;
    v_policy_count integer;
    v_all_policy_count integer;
    v_suppression_rpc_definer boolean;
    v_named_policy_count integer;
    v_has_index boolean;
    v_public_privileges text;
    v_view_definition text;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Migration bloquée : exécutez-la depuis SQL Editor avec le rôle postgres afin que les fonctions SECURITY DEFINER aient un propriétaire de confiance.';
    END IF;
    SELECT admin_user_id INTO v_admin
      FROM pg_temp._epasc_migration_admin_config;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'Migration bloquée : l''UUID vérifié du véritable administrateur du projet de test est requis.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_admin) THEN
        RAISE EXCEPTION 'Migration bloquée : l''UUID administrateur indiqué ne correspond à aucun compte auth.users de ce projet.';
    END IF;

    IF to_regclass('public.numeros') IS NULL THEN
        RAISE EXCEPTION 'Migration bloquée : public.numeros est absente.';
    END IF;
    SELECT a.atttypid INTO v_id_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.numeros'::regclass
       AND a.attname = 'id' AND NOT a.attisdropped;
    IF v_id_type IS DISTINCT FROM 'bigint'::regtype THEN
        RAISE EXCEPTION 'Migration bloquée : public.numeros.id n''est pas bigint.';
    END IF;
    SELECT EXISTS (
        SELECT 1 FROM pg_constraint c
         WHERE c.conrelid = 'public.numeros'::regclass
           AND c.contype = 'p'
           AND c.conkey = ARRAY[
               (SELECT a.attnum FROM pg_attribute a
                 WHERE a.attrelid = 'public.numeros'::regclass
                   AND a.attname = 'id' AND NOT a.attisdropped)
           ]::smallint[]
    ) INTO v_pk_ok;
    IF NOT v_pk_ok THEN
        RAISE EXCEPTION 'Migration bloquée : id n''est pas la clé primaire simple de public.numeros.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute a
         WHERE a.attrelid = 'public.numeros'::regclass
           AND a.attname = 'Nom français' AND NOT a.attisdropped
           AND a.atttypid = 'text'::regtype
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute a
         WHERE a.attrelid = 'public.numeros'::regclass
           AND a.attname = 'Nom latin' AND NOT a.attisdropped
           AND a.atttypid = 'text'::regtype
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : les colonnes de noms attendues en text sont absentes ou incompatibles.';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.numeros'::regclass) THEN
        RAISE EXCEPTION 'Migration bloquée : RLS doit être activée sur public.numeros.';
    END IF;
    IF to_regclass('public.propositions_modifications') IS NOT NULL
       OR to_regclass('public.nomenclature_admins') IS NOT NULL THEN
        RAISE EXCEPTION 'Migration bloquée : une table cible existe déjà ; auditez-la et adaptez la migration avant exécution.';
    END IF;
    IF to_regclass('public.propositions_suppression') IS NULL THEN
        RAISE EXCEPTION 'Migration bloquée : public.propositions_suppression est absente.';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.propositions_suppression'::regclass) THEN
        RAISE EXCEPTION 'Migration bloquée : RLS doit rester activée sur public.propositions_suppression.';
    END IF;
    IF NOT (
        has_table_privilege('authenticated', 'public.numeros', 'SELECT')
        AND has_table_privilege('authenticated', 'public.numeros', 'INSERT')
        AND has_table_privilege('authenticated', 'public.numeros', 'UPDATE')
        AND has_table_privilege('authenticated', 'public.numeros', 'DELETE')
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : les privilèges SQL authenticated attendus sur numeros diffèrent de l''audit ; ne les accordez pas automatiquement.';
    END IF;
    IF NOT (has_table_privilege('anon', 'public.numeros', 'SELECT')
            AND has_table_privilege('authenticated', 'public.numeros', 'SELECT')) THEN
        RAISE EXCEPTION 'Migration bloquée : les privilèges de lecture publique/authentifiée sur numeros ne correspondent pas à l''audit.';
    END IF;
    -- Relevé des privilèges non nécessaires avant leur révocation ciblée.
    RAISE NOTICE 'numeros avant migration — anon: TRUNCATE %, REFERENCES %, TRIGGER %; authenticated: TRUNCATE %, REFERENCES %, TRIGGER %',
        has_table_privilege('anon', 'public.numeros', 'TRUNCATE'),
        has_table_privilege('anon', 'public.numeros', 'REFERENCES'),
        has_table_privilege('anon', 'public.numeros', 'TRIGGER'),
        has_table_privilege('authenticated', 'public.numeros', 'TRUNCATE'),
        has_table_privilege('authenticated', 'public.numeros', 'REFERENCES'),
        has_table_privilege('authenticated', 'public.numeros', 'TRIGGER');
    SELECT string_agg(acl.privilege_type, ', ' ORDER BY acl.privilege_type)
      INTO v_public_privileges
      FROM pg_class c
      CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) acl
     WHERE c.oid = 'public.numeros'::regclass AND acl.grantee = 0;
    RAISE NOTICE 'numeros avant migration — privilèges PUBLIC : %',
        coalesce(v_public_privileges, 'aucun');
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute a
         WHERE a.attrelid = 'public.propositions_suppression'::regclass
           AND a.attname = 'numero_id' AND NOT a.attisdropped
           AND a.atttypid = 'bigint'::regtype
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute a
         WHERE a.attrelid = 'public.propositions_suppression'::regclass
           AND a.attname = 'statut' AND NOT a.attisdropped
           AND a.atttypid = 'text'::regtype
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : les colonnes numero_id bigint et statut text ne correspondent pas dans propositions_suppression.';
    END IF;
    IF to_regprocedure('public.traiter_proposition_suppression(text,boolean)') IS NULL THEN
        RAISE EXCEPTION 'Migration bloquée : la fonction de suppression attendue est absente ou sa signature diffère.';
    END IF;
    SELECT p.prosecdef INTO v_suppression_rpc_definer
      FROM pg_proc p
     WHERE p.oid = to_regprocedure('public.traiter_proposition_suppression(text,boolean)');
    IF v_suppression_rpc_definer IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Migration bloquée : la fonction de suppression existante n''est pas SECURITY DEFINER comme prévu.';
    END IF;

    -- L'audit a recensé ces deux politiques d'écriture. On exige qu'elles
    -- soient les seules applicables aux rôles navigateur avant de les retirer.
    -- Les expressions USING/WITH CHECK peuvent différer ; aucune n'est
    -- conservée comme voie d'écriture parallèle à l'allowlist.
    SELECT count(*) INTO v_policy_count
      FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
       AND p.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
       AND p.roles && ARRAY['anon'::name, 'authenticated'::name, 'public'::name];
    SELECT count(*) INTO v_named_policy_count
      FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
       AND p.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
       AND p.roles && ARRAY['anon'::name, 'authenticated'::name, 'public'::name]
       AND p.policyname IN ('Administration', 'Modification admin');
    IF v_policy_count <> 2 OR v_named_policy_count <> 2 THEN
        RAISE EXCEPTION 'Migration bloquée : les seules politiques d''écriture attendues sur numeros sont Administration et Modification admin ; auditez tout écart.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
           AND p.policyname = 'Administration' AND p.cmd = 'ALL'
           AND p.roles = ARRAY['authenticated'::name]
           AND lower(coalesce(p.qual, '')) = 'true'
           AND lower(coalesce(p.with_check, '')) = 'true'
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : Administration doit être la politique ALL authenticated avec USING et WITH CHECK true, comme dans l''audit.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
           AND p.policyname = 'Modification admin'
           AND p.cmd = 'UPDATE'
           AND p.roles = ARRAY['authenticated'::name]
           AND lower(coalesce(p.qual, '')) = 'true'
           AND lower(coalesce(p.with_check, '')) = 'true'
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : Modification admin doit être UPDATE/authenticated avec USING et WITH CHECK true, comme dans l''audit.';
    END IF;
    SELECT count(*) INTO v_all_policy_count
      FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'numeros';
    IF v_all_policy_count <> 3 OR NOT EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
           AND p.policyname = 'Lecture publique'
           AND p.cmd = 'SELECT' AND p.roles = ARRAY['anon'::name]
           AND lower(coalesce(p.qual, '')) = 'true'
           AND p.with_check IS NULL
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : les trois politiques numeros auditées, dont Lecture publique, ne correspondent pas exactement à l''état attendu.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
           AND p.policyname = 'nomenclature_authenticated_read'
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : le nom de politique nomenclature_authenticated_read est déjà utilisé.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
           AND p.cmd = 'SELECT'
           AND p.roles && ARRAY['anon'::name, 'public'::name]
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : aucune politique de lecture publique existante ne serait préservée.';
    END IF;

    -- Une seule proposition de suppression en attente par plante empêche
    -- l'insertion concurrente d'une seconde demande pendant son traitement.
    IF EXISTS (
        SELECT 1 FROM public.propositions_suppression
         WHERE statut = 'en_attente'
         GROUP BY numero_id HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : plusieurs demandes de suppression en attente existent pour une même plante.';
    END IF;
    SELECT EXISTS (
        SELECT 1
          FROM pg_index i
          JOIN pg_class ix ON ix.oid = i.indexrelid
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attname = 'numero_id'
         WHERE i.indrelid = 'public.propositions_suppression'::regclass
           AND ix.relname = 'propositions_suppression_une_en_attente_par_plante'
           AND i.indisunique AND i.indisvalid AND i.indisready
           AND i.indpred IS NOT NULL
           AND i.indnatts = 1 AND i.indkey[0] = a.attnum
           AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%statut%en_attente%'
    ) INTO v_has_index;
    IF NOT v_has_index THEN
        RAISE EXCEPTION 'Migration bloquée : l''index unique valide propositions_suppression_une_en_attente_par_plante attendu est absent ou sa définition diffère.';
    END IF;
    IF to_regclass('public.propositions_suppression_visiteur') IS NULL
       OR NOT has_table_privilege('anon', 'public.propositions_suppression_visiteur', 'SELECT') THEN
        RAISE EXCEPTION 'Migration bloquée : la vue publique utilisée par l''application pour les demandes de suppression est absente ou inaccessible.';
    END IF;
    SELECT lower(pg_get_viewdef('public.propositions_suppression_visiteur'::regclass, true))
      INTO v_view_definition;
    IF (SELECT count(*) FROM pg_attribute a
         WHERE a.attrelid = 'public.propositions_suppression_visiteur'::regclass
           AND a.attnum > 0
           AND NOT a.attisdropped) <> 1
       OR NOT EXISTS (
        SELECT 1 FROM pg_attribute a
         WHERE a.attrelid = 'public.propositions_suppression_visiteur'::regclass
           AND a.attname = 'numero_id' AND NOT a.attisdropped
           AND a.atttypid = 'bigint'::regtype
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_class c
         WHERE c.oid = 'public.propositions_suppression_visiteur'::regclass
           AND c.relkind = 'v'
    ) OR position('numero_id' IN v_view_definition) = 0
      OR position('propositions_suppression' IN v_view_definition) = 0
      OR position('statut' IN v_view_definition) = 0
      OR position('en_attente' IN v_view_definition) = 0 THEN
        RAISE EXCEPTION 'Migration bloquée : la définition de la vue visiteur ne correspond pas à la projection attendue des identifiants en attente.';
    END IF;
    IF NOT has_table_privilege('anon', 'public.propositions_suppression', 'INSERT')
       OR NOT EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'propositions_suppression'
           AND p.policyname = 'propositions_suppression_public_insert'
           AND p.cmd = 'INSERT' AND p.roles = ARRAY['anon'::name]
           AND position('en_attente' IN lower(coalesce(p.with_check, ''))) > 0
           AND position('numeros' IN lower(coalesce(p.with_check, ''))) > 0
           AND position('numero_id' IN lower(coalesce(p.with_check, ''))) > 0
    ) THEN
        RAISE EXCEPTION 'Migration bloquée : la soumission visiteur des demandes de suppression n''a pas le privilège et la politique RLS attendus.';
    END IF;

    -- La politique connue du script de suppression était lisible par tout
    -- utilisateur connecté. Si d'autres politiques SELECT existent, elles
    -- sont à analyser pour empêcher une fuite des propositions.
    SELECT count(*) INTO v_policy_count
      FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'propositions_suppression'
       AND p.cmd IN ('ALL', 'SELECT')
       AND p.roles && ARRAY['anon'::name, 'authenticated'::name, 'public'::name]
       AND p.policyname <> 'propositions_suppression_admin_select';
    IF v_policy_count <> 0 THEN
        RAISE EXCEPTION 'Migration bloquée : d''autres politiques de lecture sur propositions_suppression doivent être examinées.';
    END IF;
    SELECT count(*) INTO v_policy_count
      FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'propositions_suppression'
       AND p.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
       AND p.roles && ARRAY['anon'::name, 'authenticated'::name, 'public'::name]
       AND p.policyname <> 'propositions_suppression_public_insert';
    IF v_policy_count <> 0 THEN
        RAISE EXCEPTION 'Migration bloquée : une politique d''écriture inattendue existe sur propositions_suppression.';
    END IF;
END;
$preflight$;

-- La table conserve les snapshots des deux noms. Les champs proposés NULL
-- signifient « inchangé ». Pas de FK vers numeros : l'historique reste lisible
-- même si une plante est supprimée par le parcours existant.
CREATE TABLE public.propositions_modifications (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero_id bigint NOT NULL,
    nom_francais_origine text,
    nom_latin_origine text,
    nom_francais_propose text,
    nom_latin_propose text,
    statut text NOT NULL DEFAULT 'en_attente'
        CHECK (statut IN ('en_attente', 'acceptee', 'refusee', 'conflit')),
    cree_le timestamptz NOT NULL DEFAULT now(),
    envoyee_par uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    revue_le timestamptz,
    revue_par uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    note_admin text,
    CONSTRAINT propositions_modifications_champ_propose
        CHECK (nom_francais_propose IS NOT NULL OR nom_latin_propose IS NOT NULL),
    CONSTRAINT propositions_modifications_noms_non_vides
        CHECK ((nom_francais_propose IS NULL OR length(btrim(nom_francais_propose)) > 0)
           AND (nom_latin_propose IS NULL OR length(btrim(nom_latin_propose)) > 0))
);
CREATE INDEX propositions_modifications_statut_date_idx
    ON public.propositions_modifications (statut, cree_le);
CREATE INDEX propositions_modifications_numero_date_idx
    ON public.propositions_modifications (numero_id, cree_le DESC);

-- L'index unique existant est contrôlé en précondition et en postcondition ;
-- cette migration ne le crée ni ne le remplace.

CREATE TABLE public.nomenclature_admins (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    ajoute_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.propositions_modifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nomenclature_admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.propositions_modifications FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.nomenclature_admins FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.propositions_modifications TO authenticated;

-- Ajouter le compte fourni et vérifié avant que la transaction ne valide.
INSERT INTO public.nomenclature_admins (user_id)
SELECT admin_user_id FROM pg_temp._epasc_migration_admin_config;

CREATE OR REPLACE FUNCTION public.est_admin_nomenclature()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT auth.uid() IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM public.nomenclature_admins a
            WHERE a.user_id = auth.uid()
       );
$function$;
ALTER FUNCTION public.est_admin_nomenclature() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.est_admin_nomenclature() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.est_admin_nomenclature() TO authenticated;

CREATE POLICY propositions_modifications_admin_select
    ON public.propositions_modifications FOR SELECT TO authenticated
    USING (public.est_admin_nomenclature());

-- Soumission : lecture de la valeur officielle et insertion d'une proposition
-- uniquement. FOR KEY SHARE protège l'identité de la plante contre une
-- suppression concurrente pendant la capture des valeurs d'origine.
CREATE OR REPLACE FUNCTION public.soumettre_proposition_modification(
    p_numero_id text,
    p_nom_francais_propose text,
    p_nom_latin_propose text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_id bigint;
    v_fr text;
    v_la text;
    v_new_fr text;
    v_new_la text;
BEGIN
    IF p_numero_id IS NULL OR p_numero_id !~ '^[0-9]+$' THEN
        RAISE EXCEPTION 'Identifiant de plante invalide';
    END IF;
    SELECT n."Nom français", n."Nom latin"
      INTO v_fr, v_la
      FROM public.numeros n
     WHERE n.id = p_numero_id::bigint
     FOR KEY SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Plante introuvable'; END IF;

    v_new_fr := nullif(btrim(p_nom_francais_propose), '');
    v_new_la := nullif(btrim(p_nom_latin_propose), '');
    IF v_new_fr IS NOT DISTINCT FROM v_fr THEN v_new_fr := NULL; END IF;
    IF v_new_la IS NOT DISTINCT FROM v_la THEN v_new_la := NULL; END IF;
    IF v_new_fr IS NULL AND v_new_la IS NULL THEN
        RAISE EXCEPTION 'Aucune modification proposée';
    END IF;

    INSERT INTO public.propositions_modifications (
        numero_id, nom_francais_origine, nom_latin_origine,
        nom_francais_propose, nom_latin_propose, envoyee_par
    ) VALUES (p_numero_id::bigint, v_fr, v_la, v_new_fr, v_new_la, auth.uid())
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$function$;
ALTER FUNCTION public.soumettre_proposition_modification(text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.soumettre_proposition_modification(text, text, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.soumettre_proposition_modification(text, text, text)
    TO anon, authenticated;

-- Traitement : verrouille la proposition, puis la plante. Une modification
-- concurrente des noms produit le statut conflit et n'écrase rien. Une erreur
-- dans l'appel annule toute la transaction RPC.
CREATE OR REPLACE FUNCTION public.traiter_proposition_modification(
    p_proposition_id bigint,
    p_decision text
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_p public.propositions_modifications%ROWTYPE;
    v_fr text;
    v_la text;
BEGIN
    IF NOT public.est_admin_nomenclature() THEN
        RAISE EXCEPTION 'Accès administrateur requis';
    END IF;
    IF p_decision IS NULL OR p_decision NOT IN ('accepter', 'refuser') THEN
        RAISE EXCEPTION 'Décision invalide';
    END IF;
    SELECT * INTO v_p
      FROM public.propositions_modifications
     WHERE id = p_proposition_id
     FOR UPDATE;
    IF NOT FOUND OR v_p.statut NOT IN ('en_attente', 'conflit') THEN
        RAISE EXCEPTION 'Proposition indisponible';
    END IF;
    IF p_decision = 'refuser' THEN
        UPDATE public.propositions_modifications
           SET statut = 'refusee', revue_le = now(), revue_par = auth.uid(), note_admin = NULL
         WHERE id = v_p.id;
        RETURN 'refusee';
    END IF;
    IF v_p.statut = 'conflit' THEN RETURN 'conflit'; END IF;

    SELECT n."Nom français", n."Nom latin"
      INTO v_fr, v_la
      FROM public.numeros n
     WHERE n.id = v_p.numero_id
     FOR UPDATE;
    IF NOT FOUND
       OR (v_p.nom_francais_propose IS NOT NULL AND v_fr IS DISTINCT FROM v_p.nom_francais_origine)
       OR (v_p.nom_latin_propose IS NOT NULL AND v_la IS DISTINCT FROM v_p.nom_latin_origine) THEN
        UPDATE public.propositions_modifications
           SET statut = 'conflit', revue_le = now(), revue_par = auth.uid(),
               note_admin = 'Les champs officiels concernés ont changé depuis la soumission.'
         WHERE id = v_p.id;
        RETURN 'conflit';
    END IF;

    UPDATE public.numeros
       SET "Nom français" = CASE WHEN v_p.nom_francais_propose IS NOT NULL
                                 THEN v_p.nom_francais_propose ELSE "Nom français" END,
           "Nom latin" = CASE WHEN v_p.nom_latin_propose IS NOT NULL
                              THEN v_p.nom_latin_propose ELSE "Nom latin" END
     WHERE id = v_p.numero_id;
    UPDATE public.propositions_modifications
       SET statut = 'acceptee', revue_le = now(), revue_par = auth.uid(), note_admin = NULL
     WHERE id = v_p.id;
    RETURN 'acceptee';
END;
$function$;
ALTER FUNCTION public.traiter_proposition_modification(bigint, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.traiter_proposition_modification(bigint, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.traiter_proposition_modification(bigint, text)
    TO authenticated;

-- Remplacer les deux politiques d'écriture auditées. Les autres rôles et
-- toutes les politiques de lecture existantes sont préservés.
DROP POLICY "Administration" ON public.numeros;
DROP POLICY "Modification admin" ON public.numeros;
CREATE POLICY "Administration" ON public.numeros
    FOR ALL TO authenticated
    USING (public.est_admin_nomenclature())
    WITH CHECK (public.est_admin_nomenclature());
-- L'ancienne politique Administration ouvrait déjà la lecture à authenticated.
-- Les politiques SELECT anonymes existantes ne sont pas supprimées ni modifiées.
CREATE POLICY nomenclature_authenticated_read ON public.numeros
    FOR SELECT TO authenticated USING (true);

-- Seuls les administrateurs authentifiés gardent INSERT/UPDATE/DELETE via RLS.
-- TRUNCATE n'est pas protégé par RLS ; REFERENCES et TRIGGER ne sont pas
-- nécessaires au client. Ne pas toucher aux privilèges d'autres rôles.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON TABLE public.numeros FROM PUBLIC, anon;
REVOKE TRUNCATE, REFERENCES, TRIGGER
    ON TABLE public.numeros FROM authenticated;

-- Remplacer la lecture administrative trop large connue dans le script local.
DROP POLICY IF EXISTS propositions_suppression_admin_select
    ON public.propositions_suppression;
CREATE POLICY propositions_suppression_admin_select
    ON public.propositions_suppression FOR SELECT TO authenticated
    USING (public.est_admin_nomenclature());
REVOKE ALL ON TABLE public.propositions_suppression FROM PUBLIC, anon, authenticated;
GRANT INSERT ON TABLE public.propositions_suppression TO anon;
GRANT SELECT ON public.propositions_suppression TO authenticated;

-- La vue publique est volontairement une projection étroite : elle n'expose
-- que les identifiants des plantes avec une demande en attente. Elle s'exécute
-- avec les droits de son propriétaire (pas ceux de l'appelant) ; le propriétaire
-- de confiance postgres peut donc contourner la RLS de la table sous-jacente.
-- Le filtre et la colonne exposée sont fixés ici, la barrière limite les risques
-- de fuite par réordonnancement, et aucun droit d'écriture n'est accordé.
CREATE OR REPLACE VIEW public.propositions_suppression_visiteur
    WITH (security_barrier = true, security_invoker = false)
AS
    SELECT numero_id
      FROM public.propositions_suppression
     WHERE statut = 'en_attente';
ALTER VIEW public.propositions_suppression_visiteur OWNER TO postgres;
REVOKE ALL ON TABLE public.propositions_suppression_visiteur
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.propositions_suppression_visiteur
    TO anon, authenticated;

-- Conserver la signature, les statuts et le parcours de l'application. La RPC
-- exige maintenant l'allowlist, verrouille la demande et conserve l'atomicité.
CREATE OR REPLACE FUNCTION public.traiter_proposition_suppression(
    p_numero_id text,
    p_acceptee boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_numero_id bigint;
BEGIN
    IF NOT public.est_admin_nomenclature() THEN
        RAISE EXCEPTION 'Accès réservé à l’administration';
    END IF;
    IF p_acceptee IS NULL THEN
        RAISE EXCEPTION 'Décision invalide';
    END IF;
    IF p_numero_id IS NULL OR p_numero_id !~ '^[0-9]+$' THEN
        RAISE EXCEPTION 'Identifiant de plante invalide';
    END IF;
    v_numero_id := p_numero_id::bigint;

    -- Verrouille toutes les lignes en attente correspondantes dans un ordre
    -- stable. Le même choix est conservé que dans le parcours existant, qui
    -- traite toutes les demandes en attente portant cet identifiant.
    PERFORM ps.id
      FROM public.propositions_suppression ps
     WHERE ps.numero_id = v_numero_id AND ps.statut = 'en_attente'
     ORDER BY ps.id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Aucune demande en attente pour cette plante';
    END IF;

    IF p_acceptee THEN
        PERFORM 1 FROM public.numeros n WHERE n.id = v_numero_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'La plante associée est introuvable'; END IF;
        UPDATE public.propositions_suppression
           SET statut = 'acceptee'
         WHERE numero_id = v_numero_id AND statut = 'en_attente';
        DELETE FROM public.numeros WHERE id = v_numero_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'La plante associée est introuvable'; END IF;
    ELSE
        UPDATE public.propositions_suppression
           SET statut = 'refusee'
         WHERE numero_id = v_numero_id AND statut = 'en_attente';
    END IF;
END;
$function$;
ALTER FUNCTION public.traiter_proposition_suppression(text, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.traiter_proposition_suppression(text, boolean)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.traiter_proposition_suppression(text, boolean)
    TO authenticated;

-- Contrôles bloquants avant COMMIT : les visiteurs gardent leurs parcours de
-- proposition, mais ne disposent d'aucun DML direct sur la nomenclature.
DO $postconditions$
DECLARE
    v_count integer;
BEGIN
    -- Lecture conservée pour le client public et les utilisateurs authentifiés.
    IF NOT has_table_privilege('anon', 'public.numeros', 'SELECT')
       OR NOT has_table_privilege('authenticated', 'public.numeros', 'SELECT') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : la lecture publique/authentifiée de numeros a été perdue.';
    END IF;

    -- Aucun DML anonyme ; les droits DML authenticated restent accordés, mais
    -- leur seule politique d'écriture est protégée par l'allowlist.
    IF has_table_privilege('anon', 'public.numeros', 'INSERT')
       OR has_table_privilege('anon', 'public.numeros', 'UPDATE')
       OR has_table_privilege('anon', 'public.numeros', 'DELETE')
       OR has_table_privilege('anon', 'public.numeros', 'TRUNCATE')
       OR has_table_privilege('anon', 'public.numeros', 'REFERENCES')
       OR has_table_privilege('anon', 'public.numeros', 'TRIGGER') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : anon possède encore un privilège non autorisé sur numeros.';
    END IF;
    IF NOT (
        has_table_privilege('authenticated', 'public.numeros', 'INSERT')
        AND has_table_privilege('authenticated', 'public.numeros', 'UPDATE')
        AND has_table_privilege('authenticated', 'public.numeros', 'DELETE')
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : les privilèges DML authenticated nécessaires aux parcours admin ont changé.';
    END IF;
    IF has_table_privilege('authenticated', 'public.numeros', 'TRUNCATE')
       OR has_table_privilege('authenticated', 'public.numeros', 'REFERENCES')
       OR has_table_privilege('authenticated', 'public.numeros', 'TRIGGER') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : authenticated conserve TRUNCATE, REFERENCES ou TRIGGER sur numeros.';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM pg_class c
          CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) acl
         WHERE c.oid = 'public.numeros'::regclass
           AND acl.grantee = 0
           AND acl.privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : PUBLIC conserve un privilège d''écriture ou non nécessaire sur numeros.';
    END IF;

    -- Une seule politique d'écriture reste applicable aux rôles navigateur,
    -- et elle exige l'identité admin côté serveur pour USING et WITH CHECK.
    SELECT count(*) INTO v_count
      FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
       AND p.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
       AND p.roles && ARRAY['anon'::name, 'authenticated'::name, 'public'::name];
    IF v_count <> 1 OR NOT EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
           AND p.policyname = 'Administration' AND p.cmd = 'ALL'
           AND p.roles = ARRAY['authenticated'::name]
           AND position('est_admin_nomenclature' IN lower(coalesce(p.qual, ''))) > 0
           AND position('est_admin_nomenclature' IN lower(coalesce(p.with_check, ''))) > 0
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : une politique d''écriture numeros est absente, trop large ou non protégée par l''allowlist.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
           AND p.policyname = 'Modification admin'
    ) OR EXISTS (
        SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = 'numeros'
           AND p.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
           AND p.roles && ARRAY['anon'::name, 'public'::name]
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : l''ancienne politique ou une politique DML anonyme subsiste.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
          AND p.tablename = 'numeros' AND p.cmd = 'SELECT'
          AND p.policyname = 'Lecture publique'
          AND p.roles = ARRAY['anon'::name]
          AND lower(coalesce(p.qual, '')) = 'true'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
          AND p.tablename = 'numeros' AND p.policyname = 'nomenclature_authenticated_read'
          AND p.cmd = 'SELECT' AND p.roles = ARRAY['authenticated'::name]
          AND lower(coalesce(p.qual, '')) = 'true'
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : les politiques de lecture publique/authentifiée ne sont pas présentes.';
    END IF;

    IF NOT has_table_privilege('anon', 'public.propositions_suppression_visiteur', 'SELECT')
       OR NOT has_table_privilege('authenticated', 'public.propositions_suppression_visiteur', 'SELECT')
       OR has_table_privilege('anon', 'public.propositions_suppression', 'SELECT') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : le parcours visiteur de suppression ou la confidentialité de la table est incorrect.';
    END IF;
    IF has_table_privilege('anon', 'public.propositions_suppression_visiteur', 'INSERT')
       OR has_table_privilege('anon', 'public.propositions_suppression_visiteur', 'UPDATE')
       OR has_table_privilege('anon', 'public.propositions_suppression_visiteur', 'DELETE')
       OR has_table_privilege('anon', 'public.propositions_suppression_visiteur', 'TRUNCATE')
       OR has_table_privilege('anon', 'public.propositions_suppression_visiteur', 'REFERENCES')
       OR has_table_privilege('anon', 'public.propositions_suppression_visiteur', 'TRIGGER')
       OR has_table_privilege('authenticated', 'public.propositions_suppression_visiteur', 'INSERT')
       OR has_table_privilege('authenticated', 'public.propositions_suppression_visiteur', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.propositions_suppression_visiteur', 'DELETE')
       OR has_table_privilege('authenticated', 'public.propositions_suppression_visiteur', 'TRUNCATE')
       OR has_table_privilege('authenticated', 'public.propositions_suppression_visiteur', 'REFERENCES')
       OR has_table_privilege('authenticated', 'public.propositions_suppression_visiteur', 'TRIGGER')
       OR has_table_privilege('service_role', 'public.propositions_suppression_visiteur', 'REFERENCES')
       OR has_table_privilege('service_role', 'public.propositions_suppression_visiteur', 'TRIGGER')
       OR has_table_privilege('service_role', 'public.propositions_suppression_visiteur', 'TRUNCATE') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : un privilège superflu subsiste sur la vue visiteur.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class c
          CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) acl
         WHERE c.oid = 'public.propositions_suppression_visiteur'::regclass
           AND (
               acl.grantee = 0
               OR pg_get_userbyid(acl.grantee) NOT IN ('postgres', 'anon', 'authenticated')
               OR (pg_get_userbyid(acl.grantee) IN ('anon', 'authenticated')
                   AND acl.privilege_type <> 'SELECT')
           )
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_class c
         WHERE c.oid = 'public.propositions_suppression_visiteur'::regclass
           AND c.relkind = 'v'
           AND pg_get_userbyid(c.relowner) = 'postgres'
           AND coalesce(c.reloptions, ARRAY[]::text[]) @> ARRAY['security_barrier=true', 'security_invoker=false']::text[]
           AND (SELECT count(*) FROM pg_attribute a
                 WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) = 1
           AND position('numero_id' IN lower(pg_get_viewdef(c.oid, true))) > 0
           AND position('propositions_suppression' IN lower(pg_get_viewdef(c.oid, true))) > 0
           AND position('statut' IN lower(pg_get_viewdef(c.oid, true))) > 0
           AND position('en_attente' IN lower(pg_get_viewdef(c.oid, true))) > 0
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : la vue visiteur n''a pas un propriétaire et des options de sécurité attendus, ou PUBLIC conserve des droits.';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.propositions_suppression'::regclass) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : RLS n''est plus activée sur la table des demandes de suppression.';
    END IF;
    IF NOT has_table_privilege('anon', 'public.propositions_suppression', 'INSERT')
       OR has_table_privilege('anon', 'public.propositions_suppression', 'SELECT')
       OR has_table_privilege('anon', 'public.propositions_suppression', 'UPDATE')
       OR has_table_privilege('anon', 'public.propositions_suppression', 'DELETE')
       OR has_table_privilege('anon', 'public.propositions_suppression', 'TRUNCATE')
       OR has_table_privilege('anon', 'public.propositions_suppression', 'REFERENCES')
       OR has_table_privilege('anon', 'public.propositions_suppression', 'TRIGGER')
       OR NOT has_table_privilege('authenticated', 'public.propositions_suppression', 'SELECT')
       OR has_table_privilege('authenticated', 'public.propositions_suppression', 'INSERT')
       OR has_table_privilege('authenticated', 'public.propositions_suppression', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.propositions_suppression', 'DELETE')
       OR has_table_privilege('authenticated', 'public.propositions_suppression', 'TRUNCATE')
       OR has_table_privilege('authenticated', 'public.propositions_suppression', 'REFERENCES')
       OR has_table_privilege('authenticated', 'public.propositions_suppression', 'TRIGGER')
       OR NOT EXISTS (
        SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
          AND p.tablename = 'propositions_suppression'
          AND p.policyname = 'propositions_suppression_public_insert'
          AND p.cmd = 'INSERT' AND p.roles = ARRAY['anon'::name]
          AND position('en_attente' IN lower(coalesce(p.with_check, ''))) > 0
          AND position('numeros' IN lower(coalesce(p.with_check, ''))) > 0
          AND position('numero_id' IN lower(coalesce(p.with_check, ''))) > 0
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : les privilèges et la politique RLS de soumission visiteur de suppression sont incorrects.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
          AND p.tablename = 'propositions_suppression'
          AND p.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
          AND p.roles && ARRAY['anon'::name, 'authenticated'::name, 'public'::name]
          AND p.policyname <> 'propositions_suppression_public_insert'
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : une voie RLS d''écriture inattendue subsiste sur propositions_suppression.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
          AND p.tablename = 'propositions_suppression'
          AND p.policyname = 'propositions_suppression_admin_select'
          AND p.cmd = 'SELECT' AND p.roles = ARRAY['authenticated'::name]
          AND position('est_admin_nomenclature' IN lower(coalesce(p.qual, ''))) > 0
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : la lecture des propositions de suppression n''est pas réservée aux administrateurs.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
          AND p.tablename = 'propositions_modifications'
          AND p.policyname = 'propositions_modifications_admin_select'
          AND p.cmd = 'SELECT' AND p.roles = ARRAY['authenticated'::name]
          AND position('est_admin_nomenclature' IN lower(coalesce(p.qual, ''))) > 0
    ) OR NOT has_table_privilege('authenticated', 'public.propositions_modifications', 'SELECT')
      OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.propositions_modifications'::regclass)
      OR has_table_privilege('anon', 'public.propositions_modifications', 'SELECT')
      OR has_table_privilege('anon', 'public.propositions_modifications', 'INSERT')
      OR has_table_privilege('anon', 'public.propositions_modifications', 'UPDATE')
      OR has_table_privilege('anon', 'public.propositions_modifications', 'DELETE')
      OR has_table_privilege('anon', 'public.propositions_modifications', 'TRUNCATE')
      OR has_table_privilege('anon', 'public.propositions_modifications', 'REFERENCES')
      OR has_table_privilege('anon', 'public.propositions_modifications', 'TRIGGER')
      OR has_table_privilege('authenticated', 'public.propositions_modifications', 'INSERT')
      OR has_table_privilege('authenticated', 'public.propositions_modifications', 'UPDATE')
      OR has_table_privilege('authenticated', 'public.propositions_modifications', 'DELETE')
      OR has_table_privilege('authenticated', 'public.propositions_modifications', 'TRUNCATE')
      OR has_table_privilege('authenticated', 'public.propositions_modifications', 'REFERENCES')
      OR has_table_privilege('authenticated', 'public.propositions_modifications', 'TRIGGER') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : les propositions de correction ne sont pas réservées aux administrateurs.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_index i
          JOIN pg_class ix ON ix.oid = i.indexrelid
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attname = 'numero_id'
         WHERE i.indrelid = 'public.propositions_suppression'::regclass
           AND ix.relname = 'propositions_suppression_une_en_attente_par_plante'
           AND i.indisunique AND i.indisvalid AND i.indisready
           AND i.indpred IS NOT NULL
           AND i.indnatts = 1 AND i.indkey[0] = a.attnum
           AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%statut%en_attente%'
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : l''unicité des demandes de suppression en attente par plante n''est pas garantie.';
    END IF;

    IF has_function_privilege('anon', 'public.traiter_proposition_modification(bigint,text)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.traiter_proposition_modification(bigint,text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.est_admin_nomenclature()', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.est_admin_nomenclature()', 'EXECUTE')
       OR has_function_privilege('anon', 'public.traiter_proposition_suppression(text,boolean)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.traiter_proposition_suppression(text,boolean)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : droits EXECUTE inattendus sur les fonctions de traitement.';
    END IF;
    IF NOT has_function_privilege('anon', 'public.soumettre_proposition_modification(text,text,text)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.soumettre_proposition_modification(text,text,text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : la soumission de proposition n''est pas accessible comme prévu.';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM pg_proc p
          CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) acl
         WHERE p.oid IN (
             to_regprocedure('public.est_admin_nomenclature()'),
             to_regprocedure('public.soumettre_proposition_modification(text,text,text)'),
             to_regprocedure('public.traiter_proposition_modification(bigint,text)'),
             to_regprocedure('public.traiter_proposition_suppression(text,boolean)')
         )
           AND acl.grantee = 0
           AND acl.privilege_type = 'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : PUBLIC conserve EXECUTE sur une fonction SECURITY DEFINER.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p
         WHERE p.oid IN (
             to_regprocedure('public.est_admin_nomenclature()'),
             to_regprocedure('public.soumettre_proposition_modification(text,text,text)'),
             to_regprocedure('public.traiter_proposition_modification(bigint,text)'),
             to_regprocedure('public.traiter_proposition_suppression(text,boolean)')
         )
           AND (NOT p.prosecdef
                OR pg_get_userbyid(p.proowner) <> 'postgres'
                OR NOT coalesce(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public']::text[])
    ) THEN
        RAISE EXCEPTION 'Post-contrôle échoué : une fonction SECURITY DEFINER n''a pas le propriétaire postgres ou le search_path attendu.';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.nomenclature_admins'::regclass)
       OR has_table_privilege('anon', 'public.nomenclature_admins', 'SELECT')
       OR has_table_privilege('anon', 'public.nomenclature_admins', 'INSERT')
       OR has_table_privilege('anon', 'public.nomenclature_admins', 'UPDATE')
       OR has_table_privilege('anon', 'public.nomenclature_admins', 'DELETE')
       OR has_table_privilege('anon', 'public.nomenclature_admins', 'TRUNCATE')
       OR has_table_privilege('anon', 'public.nomenclature_admins', 'REFERENCES')
       OR has_table_privilege('anon', 'public.nomenclature_admins', 'TRIGGER')
       OR has_table_privilege('authenticated', 'public.nomenclature_admins', 'SELECT')
       OR has_table_privilege('authenticated', 'public.nomenclature_admins', 'INSERT')
       OR has_table_privilege('authenticated', 'public.nomenclature_admins', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.nomenclature_admins', 'DELETE')
       OR has_table_privilege('authenticated', 'public.nomenclature_admins', 'TRUNCATE')
       OR has_table_privilege('authenticated', 'public.nomenclature_admins', 'REFERENCES')
       OR has_table_privilege('authenticated', 'public.nomenclature_admins', 'TRIGGER') THEN
        RAISE EXCEPTION 'Post-contrôle échoué : RLS ou confidentialité de la liste administrative est incorrecte.';
    END IF;
END;
$postconditions$;

-- Vérifications post-migration (résultats à contrôler dans SQL Editor) :
-- SELECT to_regclass('public.propositions_modifications'),
--        to_regclass('public.nomenclature_admins');
-- SELECT table_name, column_name, data_type
--   FROM information_schema.columns
--  WHERE table_schema = 'public'
--    AND table_name IN ('propositions_modifications','nomenclature_admins','propositions_suppression')
--  ORDER BY table_name, ordinal_position;
-- SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS signature,
--        p.prosecdef AS security_definer, p.proconfig,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_exec
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--  WHERE n.nspname = 'public' AND p.proname IN (
--      'est_admin_nomenclature','soumettre_proposition_modification',
--      'traiter_proposition_modification','traiter_proposition_suppression');
-- SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
--   FROM pg_policies WHERE schemaname = 'public'
--    AND tablename IN ('numeros','propositions_modifications','propositions_suppression');
-- SELECT grantee, table_name, privilege_type FROM information_schema.role_table_grants
--  WHERE table_schema = 'public'
--    AND table_name IN ('numeros','propositions_modifications','propositions_suppression')
--  ORDER BY table_name, grantee, privilege_type;

COMMIT;
