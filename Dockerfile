FROM ruby:2.7.5
# ベースにするイメージを指定

RUN mkdir /myapp
# コンテナ内にmyappディレクトリを作成
RUN gem install bundler

WORKDIR /myapp
# 作成したmyappディレクトリを作業用ディレクトリとして設定

COPY Gemfile /myapp/Gemfile
COPY Gemfile.lock /myapp/Gemfile.lock
# ローカルの Gemfile と Gemfile.lock をコンテナ内のmyapp配下にコピー
RUN bundle install
# コンテナ内にコピーした Gemfile の bundle install

COPY . /myapp
# ローカルのmyapp配下のファイルをコンテナ内のmyapp配下にコピー