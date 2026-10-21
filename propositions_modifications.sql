-- Nomenclature EPASC — propositions de modification des noms
-- Préparation locale uniquement : ce fichier n'a pas été exécuté.
-- À relire puis exécuter manuellement sur Supabase de test après vérification
-- du type de numeros.id, des privilèges/RLS existants et de l'identité admin.

begin;

create table if not exists public.propositions_modifications (
    id bigint generated always as identity primary key,
    numero_id text not null,
    nom_francais_origine text,
    nom_latin_origine text,
    nom_francais_propose text,
    nom_latin_propose text,
    statut text not null default 'en_attente'
        check (statut in ('en_attente', 'acceptee', 'refusee', 'conflit')),
    cree_le timestamptz not null default now(),
    envoyee_par uuid references auth.users(id) on delete set null,
    revue_le timestamptz,
    revue_par uuid references auth.users(id) on delete set null,
    note_admin text,
    constraint propositions_modifications_champ_propose
        check (nom_francais_propose is not null or nom_latin_propose is not null),
    constraint propositions_modifications_noms_non_vides
        check ((nom_francais_propose is null or length(btrim(nom_francais_propose)) > 0)
           and (nom_latin_propose is null or length(btrim(nom_latin_propose)) > 0))
);

create index if not exists propositions_modifications_statut_date_idx
    on public.propositions_modifications (statut, cree_le);
create index if not exists propositions_modifications_numero_date_idx
    on public.propositions_modifications (numero_id, cree_le desc);

-- Liste d'autorisation spécifique à cette fonctionnalité. Elle démarre vide.
create table if not exists public.nomenclature_admins (
    user_id uuid primary key references auth.users(id) on delete cascade,
    ajoute_le timestamptz not null default now()
);

alter table public.propositions_modifications enable row level security;
alter table public.nomenclature_admins enable row level security;
revoke all on public.propositions_modifications from public, anon, authenticated;
revoke all on public.nomenclature_admins from public, anon, authenticated;
grant select on public.propositions_modifications to authenticated;

create or replace function public.est_admin_nomenclature()
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
    select auth.uid() is not null
       and exists (select 1 from public.nomenclature_admins a where a.user_id = auth.uid());
$$;
revoke all on function public.est_admin_nomenclature() from public, anon;
grant execute on function public.est_admin_nomenclature() to authenticated;

drop policy if exists propositions_modifications_admin_select on public.propositions_modifications;
create policy propositions_modifications_admin_select
    on public.propositions_modifications for select to authenticated
    using (public.est_admin_nomenclature());

-- La soumission relit la valeur officielle côté serveur et insère seulement
-- une proposition. Les champs inchangés deviennent NULL.
create or replace function public.soumettre_proposition_modification(
    p_numero_id text, p_nom_francais_propose text, p_nom_latin_propose text
) returns bigint language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
    v_fr text; v_la text; v_new_fr text; v_new_la text; v_id bigint;
begin
    select n."Nom français", n."Nom latin" into v_fr, v_la
      from public.numeros n where n.id::text = p_numero_id;
    if not found then raise exception 'Plante introuvable'; end if;
    v_new_fr := nullif(btrim(p_nom_francais_propose), '');
    v_new_la := nullif(btrim(p_nom_latin_propose), '');
    if v_new_fr is null or v_new_la is null then raise exception 'Les deux noms doivent être fournis'; end if;
    if v_new_fr is not distinct from v_fr then v_new_fr := null; end if;
    if v_new_la is not distinct from v_la then v_new_la := null; end if;
    if v_new_fr is null and v_new_la is null then raise exception 'Aucune modification proposée'; end if;
    insert into public.propositions_modifications (
        numero_id, nom_francais_origine, nom_latin_origine,
        nom_francais_propose, nom_latin_propose, envoyee_par
    ) values (p_numero_id, v_fr, v_la, v_new_fr, v_new_la, auth.uid()) returning id into v_id;
    return v_id;
end;
$$;
revoke all on function public.soumettre_proposition_modification(text, text, text) from public;
grant execute on function public.soumettre_proposition_modification(text, text, text) to anon, authenticated;

-- Verrouillage et comparaison des snapshots avant toute modification officielle.
create or replace function public.traiter_proposition_modification(
    p_proposition_id bigint, p_decision text
) returns text language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
    p public.propositions_modifications%rowtype; v_fr text; v_la text;
begin
    if not public.est_admin_nomenclature() then raise exception 'Accès administrateur requis'; end if;
    if p_decision not in ('accepter', 'refuser') then raise exception 'Décision invalide'; end if;
    select * into p from public.propositions_modifications where id = p_proposition_id for update;
    if not found or p.statut not in ('en_attente', 'conflit') then raise exception 'Proposition indisponible'; end if;
    if p_decision = 'refuser' then
        update public.propositions_modifications set statut='refusee', revue_le=now(), revue_par=auth.uid(), note_admin=null where id=p.id;
        return 'refusee';
    end if;
    if p.statut = 'conflit' then return 'conflit'; end if;
    select n."Nom français", n."Nom latin" into v_fr, v_la
      from public.numeros n where n.id::text = p.numero_id for update;
    if not found
       or (p.nom_francais_propose is not null and v_fr is distinct from p.nom_francais_origine)
       or (p.nom_latin_propose is not null and v_la is distinct from p.nom_latin_origine) then
        update public.propositions_modifications set statut='conflit', revue_le=now(), revue_par=auth.uid(),
            note_admin='Les champs officiels concernés ont changé depuis la soumission.' where id=p.id;
        return 'conflit';
    end if;
    update public.numeros
       set "Nom français" = case when p.nom_francais_propose is not null then p.nom_francais_propose else "Nom français" end,
           "Nom latin" = case when p.nom_latin_propose is not null then p.nom_latin_propose else "Nom latin" end
     where id::text = p.numero_id;
    update public.propositions_modifications set statut='acceptee', revue_le=now(), revue_par=auth.uid(), note_admin=null where id=p.id;
    return 'acceptee';
end;
$$;
revoke all on function public.traiter_proposition_modification(bigint, text) from public, anon;
grant execute on function public.traiter_proposition_modification(bigint, text) to authenticated;

-- L'API anonyme ne peut pas modifier la nomenclature officielle. Vérifier que
-- cette révocation correspond aux privilèges voulus avant exécution en test.
revoke insert, update, delete on public.numeros from public, anon;

commit;

-- Après exécution sur la base de test, autoriser explicitement un compte admin :
-- insert into public.nomenclature_admins(user_id) values ('UUID_DU_COMPTE_ADMIN');
