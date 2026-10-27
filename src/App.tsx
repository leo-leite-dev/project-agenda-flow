import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'

import { AuthProvider } from './contexts/AuthProvider'
import { ProtectedRoute } from './components/ProtectedRoute'
import { AuthCallbackPage } from './pages/AuthCallbackPage'
import { CreateEstablishmentPage } from './pages/CreateEstablishmentPage'
import { DashboardPage } from './pages/DashboardPage'
import { DashboardModulePage } from './pages/DashboardModulePage'
import { HomePage } from './pages/HomePage'
import { LoginPage } from './pages/LoginPage'
import { SelectEstablishmentPage } from './pages/SelectEstablishmentPage'
import { WelcomePage } from './pages/WelcomePage'

import './App.css'

function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/login" element={<LoginPage />} />
          <Route path="/auth/callback" element={<AuthCallbackPage />} />
          <Route
            path="/welcome"
            element={
              <ProtectedRoute>
                <WelcomePage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/establishment/new"
            element={
              <ProtectedRoute>
                <CreateEstablishmentPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/select-establishment"
            element={
              <ProtectedRoute>
                <SelectEstablishmentPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/dashboard"
            element={
              <ProtectedRoute>
                <DashboardPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/dashboard/:module"
            element={
              <ProtectedRoute>
                <DashboardModulePage />
              </ProtectedRoute>
            }
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  )
}

export default App
