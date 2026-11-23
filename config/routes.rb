# frozen_string_literal: true

OpenProject::Application.routes.draw do
  scope 'projects/:project_id', as: 'project' do
    resources :seismic_jobs, controller: 'seismic_jobs', only: %i[index new create show destroy] do
      collection do
        get :status
      end
      member do
        post :cancel
        post :retry
        post :publish
        get :confirm_delete
        get 'results/:result_id/image', action: :image, as: :result_image
      end
    end

    resources :seismic_models, controller: 'seismic_models', only: %i[index new create show destroy] do
      collection do
        get :status
        get :source
      end
      member do
        post :cancel
        post :retry
        get :confirm_delete
        get 'files/:kind', action: :file, as: :file
      end
    end

    resources :seismic_suggestions, controller: 'seismic_suggestions', only: %i[index] do
      member do
        post :confirm
        post :reject
        post :reopen
      end
    end

    resources :seismic_aedes, controller: 'seismic_aedes', only: %i[index show create update destroy] do
      member do
        get :print
        post :prefill
      end
    end
  end
end
