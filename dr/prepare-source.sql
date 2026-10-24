CREATE TABLE IF NOT EXISTS public.dr_evidence (
 id integer PRIMARY KEY,
 message text NOT NULL
);
INSERT INTO public.dr_evidence VALUES
 (1,'AWS Azure GCP disaster recovery test'),
 (2,'Snapshot backup validation')
ON CONFLICT (id) DO NOTHING;
SELECT * FROM public.dr_evidence ORDER BY id;
