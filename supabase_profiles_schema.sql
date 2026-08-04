-- Run this in Supabase Dashboard > SQL Editor to enable user registration (create login credentials).
-- Creates the profiles table used by the app for storing user details.

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  full_name text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT 'user',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Allow users to read their own profile.
DROP POLICY IF EXISTS "Allow users to read own profile" ON public.profiles;
CREATE POLICY "Allow users to read own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

-- Allow users to insert/update their own profile.
DROP POLICY IF EXISTS "Allow users to upsert own profile" ON public.profiles;
CREATE POLICY "Allow users to upsert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Allow users to update own profile" ON public.profiles;
CREATE POLICY "Allow users to update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Allow anon to create a profile row during signup (first time).
-- NOTE: This is a convenience for self-service signup. For stricter security,
-- remove this policy and instead create the profile via a database trigger.
DROP POLICY IF EXISTS "Allow anon profile insert" ON public.profiles;
CREATE POLICY "Allow anon profile insert"
  ON public.profiles FOR INSERT
  TO anon
  WITH CHECK (true);
