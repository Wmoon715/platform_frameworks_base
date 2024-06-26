/*
 * Copyright (C) 2020 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.android.systemui.util.settings;

import android.content.ContentResolver;
import android.net.Uri;
import android.provider.Settings;

import androidx.annotation.NonNull;

import com.android.systemui.settings.UserTracker;

import javax.inject.Inject;

class SystemSettingsImpl implements SystemSettings {
    private final ContentResolver mContentResolver;
    private final UserTracker mUserTracker;

    @Inject
    SystemSettingsImpl(ContentResolver contentResolver, UserTracker userTracker) {
        mContentResolver = contentResolver;
        mUserTracker = userTracker;
    }

    @Override
    public ContentResolver getContentResolver() {
        return mContentResolver;
    }

    @Override
    public UserTracker getUserTracker() {
        return mUserTracker;
    }

    @Override
    public Uri getUriFor(String name) {
        return Settings.System.getUriFor(name);
    }

    @Override
    public String getStringForUser(String name, int userHandle) {
        return Settings.System.getStringForUser(mContentResolver, name,
                getRealUserHandle(userHandle));
    }

    @Override
    public boolean putString(String name, String value, boolean overrideableByRestore) {
        return Settings.System.putString(mContentResolver, name, value, overrideableByRestore);
    }

    @Override
    public boolean putStringForUser(String name, String value, int userHandle) {
        return Settings.System.putStringForUser(mContentResolver, name, value,
                getRealUserHandle(userHandle));
    }

    @Override
    public boolean putStringForUser(String name, String value, String tag, boolean makeDefault,
            int userHandle, boolean overrideableByRestore) {
        throw new UnsupportedOperationException(
                "This method only exists publicly for Settings.Secure and Settings.Global");
    }

    @Override
    public boolean putString(@NonNull String name, String value, String tag, boolean makeDefault) {
        throw new UnsupportedOperationException(
                "This method only exists publicly for Settings.Secure and Settings.Global");
    }
}
